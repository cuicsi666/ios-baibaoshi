/*===================================================================*/
/*  InfoNES_System_iOS.cpp : iOS platform layer for InfoNES          */
/*  基于 SDL 版改造：帧就绪信号 + 环形音频缓冲 + Swift C 接口        */
/*===================================================================*/

#include "InfoNES.h"
#include "InfoNES_System.h"
#include "InfoNES_pAPU.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/time.h>

/*-------------------------------------------------------------------*/
/*  iOS 桥接状态                                                      */
/*-------------------------------------------------------------------*/
static pthread_t gNesThread;
static pthread_mutex_t gFrameLock = PTHREAD_MUTEX_INITIALIZER;
static volatile int gRunning = 0;
static volatile int gQuitReq = 0;
static volatile int gFrameReady = 0;
static volatile unsigned int gPadBits = 0;
static int gStartError = 0;
static char gRomPath[1024];
static char gRomBase[256];

// 音频环形缓冲（16bit mono）
#define NES_RING_SIZE 32768
static short gRing[NES_RING_SIZE];
static volatile int gRingRead = 0;
static volatile int gRingWrite = 0;
static int gSampleRate = 22050;
static int gSamplesPerSync = 735;
static volatile int gPrefilled = 0;
static short gLastSample = 0;

extern int LoadSRAM();
extern int SaveSRAM();

/*-------------------------------------------------------------------*/
/*  Palette（RGB565）                                                 */
/*-------------------------------------------------------------------*/
static const unsigned char NesPaletteRGB[ 64 ][ 3 ] =
{
   112, 112, 112,     32,  24, 136,      0,   0, 168,     64,   0, 152,
   136,   0, 112,    168,   0,  16,    160,   0,   0,    120,   8,   0,
    64,  40,   0,      0,  64,   0,      0,  80,   0,      0,  56,  16,
    24,  56,  88,      0,   0,   0,      0,   0,   0,      0,   0,   0,
   184, 184, 184,      0, 112, 232,     32,  56, 232,    128,   0, 240,
   184,   0, 184,    224,   0,  88,    216,  40,   0,    200,  72,   8,
   136, 112,   0,      0, 144,   0,      0, 168,   0,      0, 144,  56,
     0, 128, 136,      0,   0,   0,      0,   0,   0,      0,   0,   0,
   248, 248, 248,     56, 184, 248,     88, 144, 248,     64, 136, 248,
   240, 120, 248,    248, 112, 176,    248, 112,  96,    248, 152,  56,
   240, 184,  56,    128, 208,  16,     72, 216,  72,     88, 248, 152,
     0, 232, 216,      0,   0,   0,      0,   0,   0,      0,   0,   0,
   248, 248, 248,    168, 224, 248,    192, 208, 248,    208, 200, 248,
   248, 192, 248,    248, 192, 216,    248, 184, 176,    248, 216, 168,
   248, 224, 160,    224, 248, 160,    168, 240, 184,    176, 248, 200,
   152, 248, 240,      0,   0,   0,      0,   0,   0,      0,   0,   0,
};
WORD NesPalette[ 64 ];

static void BuildPalette(void) {
  for (int i = 0; i < 64; i++) {
    unsigned r = NesPaletteRGB[i][0], g = NesPaletteRGB[i][1], b = NesPaletteRGB[i][2];
    NesPalette[i] = (WORD)(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
  }
}

/*-------------------------------------------------------------------*/
/*  系统层实现                                                         */
/*-------------------------------------------------------------------*/

int InfoNES_Menu() {
  // gQuitReq 置位时让主循环退出
  return gQuitReq ? -1 : 0;
}

int InfoNES_ReadRom( const char *pszFileName ) {
  FILE *fp = fopen(pszFileName, "rb");
  if (fp == NULL) return -1;

  fread( &NesHeader, sizeof( NesHeader ), 1, fp );
  if ( memcmp( NesHeader.byID, "NES\x1a", 4 ) != 0 ) {
    fclose( fp );
    return -1;
  }

  memset( SRAM, 0, SRAM_SIZE );

  if ( NesHeader.byInfo1 & 4 ) {
    fread( &SRAM[ 0x1000 ], 512, 1, fp );
  }

  ROM = (BYTE *)malloc( NesHeader.byRomSize * 0x4000 );
  fread( ROM, 0x4000, NesHeader.byRomSize, fp );

  if ( NesHeader.byVRomSize > 0 ) {
    VROM = (BYTE *)malloc( NesHeader.byVRomSize * 0x2000 );
    fread( VROM, 0x2000, NesHeader.byVRomSize, fp );
  }

  fclose( fp );
  return 0;
}

void InfoNES_ReleaseRom() {
  if ( ROM ) { free( ROM ); ROM = NULL; }
  if ( VROM ) { free( VROM ); VROM = NULL; }
}

/* 每帧回调：60.098fps 帧率限制 + 帧就绪标记 */
void InfoNES_LoadFrame() {
  /* 帧率限制 + 音频水位自适应：缓冲水位决定帧间隔（音频永不欠载） */
  static long long nextFrameUs = 0;
  struct timeval now;
  gettimeofday( &now, NULL );
  long long nowUs = (long long)now.tv_sec * 1000000LL + now.tv_usec;
  if ( nextFrameUs == 0 ) nextFrameUs = nowUs;
  if ( nowUs < nextFrameUs ) {
    usleep( (useconds_t)( nextFrameUs - nowUs ) );
  }
  int avail = ( gRingWrite - gRingRead + NES_RING_SIZE ) % NES_RING_SIZE;
  long long step;                        // 60.098fps 基准，水位微调 ±1.5%
  if ( avail > 22050 )      step = 16800;  // 高水位：放慢
  else if ( avail < 4410 )  step = 16450;  // 低水位：加快
  else                      step = 16639;
  nextFrameUs += step;
  gettimeofday( &now, NULL );
  nowUs = (long long)now.tv_sec * 1000000LL + now.tv_usec;
  if ( nextFrameUs < nowUs - 100000 )    // 落后超过 100ms 直接归位
    nextFrameUs = nowUs;

  pthread_mutex_lock( &gFrameLock );
  gFrameReady = 1;
  pthread_mutex_unlock( &gFrameLock );
}

void InfoNES_PadState( DWORD *pdwPad1, DWORD *pdwPad2, DWORD *pdwSystem ) {
  *pdwPad1 = (DWORD)gPadBits;
  *pdwPad2 = 0;
  *pdwSystem = 0;
}

void *InfoNES_MemoryCopy( void *dest, const void *src, int count ) {
  return memcpy( dest, src, count );
}

void *InfoNES_MemorySet( void *dest, int c, int count ) {
  return memset( dest, c, count );
}

void InfoNES_DebugPrint( char *pszMsg ) { /* 静默 */ }
void InfoNES_Wait() { /* 帧节拍由核心时序控制 */ }

/* Sound Open：核心通知采样参数 */
int InfoNES_SoundOpen( int samples_per_sync, int sample_rate ) {
  gSampleRate = sample_rate;
  gSamplesPerSync = samples_per_sync;
  gRingRead = gRingWrite = 0;
  gPrefilled = 0;
  gLastSample = 0;
  return 1;
}

/* 5 通道波形混合写入环形缓冲（供 AVAudioEngine 拉流） */
void InfoNES_SoundOutput( int samples, BYTE *wave1, BYTE *wave2, BYTE *wave3, BYTE *wave4, BYTE *wave5 ) {
  for ( int i = 0; i < samples; i++ ) {
    int sum = ( wave1[i] + wave2[i] + wave3[i] + wave4[i] + wave5[i] ) / 5;
    int v = ( sum - 128 ) * 384;          // 8bit 无符号中心化 → 16bit，增益 1.5x
    if ( v > 32767 ) v = 32767;
    if ( v < -32768 ) v = -32768;
    int next = ( gRingWrite + 1 ) % NES_RING_SIZE;
    if ( next != gRingRead ) {            // 满则丢弃（防阻塞模拟器线程）
      gRing[ gRingWrite ] = (short)v;
      gRingWrite = next;
    }
  }
}

void InfoNES_SoundClose() {
  gRingRead = gRingWrite = 0;
}

/* pAPUInit 调用 */
void InfoNES_SoundInit( void ) {
  gRingRead = gRingWrite = 0;
}

/* 错误提示框（Reset 失败时调用）——静默打日志 */
void InfoNES_MessageBox( char *pszMsg, ... ) {
  (void)pszMsg;
}

/*-------------------------------------------------------------------*/
/*  SRAM 存档（<savDir>/<rom>.sav，目录由 Swift 注入）                  */
/*-------------------------------------------------------------------*/
static char gSavDir[512] = "/tmp";

static void MakeSavPath( char *out, size_t len ) {
  snprintf( out, len, "%s/%s.sav", gSavDir, gRomBase );
}

int LoadSRAM() {
  char path[600];
  FILE *fp;
  unsigned char pSrcBuf[ SRAM_SIZE ];
  unsigned char chData, chTag;
  int nRunLen, nDecoded, nDecLen, nIdx;

  MakeSavPath( path, sizeof( path ) );
  fp = fopen( path, "rb" );
  if ( fp == NULL ) return -1;

  nIdx = 0; nDecoded = 0;
  while ( ( nDecoded < SRAM_SIZE ) && ( fread( &chTag, 1, 1, fp ) != 0 ) ) {
    fread( &chData, 1, 1, fp );
    if ( chTag == 0 ) {
      pSrcBuf[ nDecoded++ ] = chData;
    } else {
      fread( &nRunLen, 1, 2, fp );
      for ( nRunLen++; nRunLen > 0; nRunLen-- )
        pSrcBuf[ nDecoded++ ] = chData;
    }
    nIdx++;
  }
  memcpy( SRAM, pSrcBuf, SRAM_SIZE );
  fclose( fp );
  return 0;
}

int SaveSRAM() {
  char path[600];
  FILE *fp;
  int nRunLen, nIdx, nDecoded;
  unsigned char pCntBuf[ SRAM_SIZE ];
  unsigned char chData;
  unsigned char chTag;

  MakeSavPath( path, sizeof( path ) );
  fp = fopen( path, "wb" );
  if ( fp == NULL ) return -1;

  nIdx = 0; nDecoded = 0;
  while ( nIdx < SRAM_SIZE ) {
    chData = SRAM[ nIdx ];
    nRunLen = 1;
    nIdx++;
    while ( SRAM[ nIdx ] == chData && nRunLen < 255 && nIdx < SRAM_SIZE ) {
      nRunLen++; nIdx++;
    }
    if ( nRunLen == 1 && chData != 0 ) {
      pCntBuf[ nDecoded++ ] = 0;
      pCntBuf[ nDecoded++ ] = chData;
    } else {
      chTag = 1;
      pCntBuf[ nDecoded++ ] = chTag;
      pCntBuf[ nDecoded++ ] = chData;
      pCntBuf[ nDecoded++ ] = (unsigned char)( nRunLen - 1 );
      pCntBuf[ nDecoded++ ] = (unsigned char)( ( nRunLen - 1 ) >> 8 );
    }
  }
  fwrite( pCntBuf, 1, nDecoded, fp );
  fclose( fp );
  return 0;
}

/*-------------------------------------------------------------------*/
/*  模拟线程                                                           */
/*-------------------------------------------------------------------*/
static void *NesThreadFunc( void *arg ) {
  InfoNES_Main();          // 内部死循环，InfoNES_Menu 返回 -1 时退出
  gRunning = 0;
  return NULL;
}

/*-------------------------------------------------------------------*/
/*  对 Swift 的 C 接口                                                 */
/*-------------------------------------------------------------------*/
extern "C" {

// 设置 SRAM 存档目录（Swift 注入 Documents 路径）
void nes_set_sav_dir( const char *dir ) {
  strncpy( gSavDir, dir, sizeof( gSavDir ) - 1 );
}

// 启动模拟器：0 成功
int nes_start( const char *romPath ) {
  if ( gRunning ) return 1;
  strncpy( gRomPath, romPath, sizeof( gRomPath ) - 1 );
  const char *base = strrchr( romPath, '/' );
  strncpy( gRomBase, base ? base + 1 : romPath, sizeof( gRomBase ) - 1 );

  BuildPalette();
  gStartError = 0;
  // 与 SDL 版一致：Load 后由 InfoNES_Main 内部 Init（避免重复初始化）
  if ( InfoNES_Load( gRomPath ) != 0 ) {
    InfoNES_ReleaseRom();
    gStartError = -1;
    return -1;
  }
  gQuitReq = 0;
  gRunning = 1;
  pthread_create( &gNesThread, NULL, NesThreadFunc, NULL );
  pthread_detach( gNesThread );
  return 0;
}

// 停止：请求退出 → join 线程（core 在 Main 末尾自释放）→ 存 SRAM
void nes_stop( void ) {
  if ( !gRunning ) return;
  gQuitReq = 1;
  pthread_join( gNesThread, NULL );   // 线程内 InfoNES_Main 已调用 InfoNES_Fin
  gRunning = 0;
  SaveSRAM();
}

int nes_running( void ) { return gRunning; }

// 手柄：bit0=A bit1=B bit2=Select bit3=Start bit4=U bit5=D bit6=L bit7=R
void nes_set_pad( unsigned int bits ) { gPadBits = bits; }

// 帧就绪查询：1 = WorkFrame 有新帧
int nes_frame_ready( void ) {
  int r = gFrameReady;
  gFrameReady = 0;
  return r;
}

// 拷贝当前帧（RGB565 256x240），返回像素数（与模拟器线程互斥）
int nes_frame_copy( unsigned short *out ) {
  pthread_mutex_lock( &gFrameLock );
  memcpy( out, WorkFrame, sizeof( WorkFrame ) );
  pthread_mutex_unlock( &gFrameLock );
  return NES_DISP_WIDTH * NES_DISP_HEIGHT;
}

// 拷贝当前帧并转 RGBA8（C 循环，比 Swift 快）
int nes_frame_copy_rgba( unsigned char *out ) {
  pthread_mutex_lock( &gFrameLock );
  int total = NES_DISP_WIDTH * NES_DISP_HEIGHT;
  WORD *pw = WorkFrame;
  for ( int i = 0; i < total; i++ ) {
    WORD px = pw[ i ];
    out[ i * 4 ]     = (unsigned char)( ( ( px >> 11 ) & 0x1f ) * 255 / 31 );
    out[ i * 4 + 1 ] = (unsigned char)( ( ( px >> 5 ) & 0x3f ) * 255 / 63 );
    out[ i * 4 + 2 ] = (unsigned char)( ( px & 0x1f ) * 255 / 31 );
    out[ i * 4 + 3 ] = 255;
  }
  pthread_mutex_unlock( &gFrameLock );
  return total;
}

int nes_last_error( void ) { return gStartError; }

// 音频拉流：预填充门槛（防启动爆音）+ 欠载 hold 上一样本（平滑）
int nes_audio_pull( short *out, int maxSamples ) {
  int avail = ( gRingWrite - gRingRead + NES_RING_SIZE ) % NES_RING_SIZE;
  if ( !gPrefilled ) {
    if ( avail < 8192 ) {                       // 预填约 186ms 再开播
      memset( out, 0, maxSamples * sizeof( short ) );
      return maxSamples;
    }
    gPrefilled = 1;
  }
  int n = 0;
  while ( gRingRead != gRingWrite && n < maxSamples ) {
    gLastSample = gRing[ gRingRead ];
    out[ n++ ] = gLastSample;
    gRingRead = ( gRingRead + 1 ) % NES_RING_SIZE;
  }
  while ( n < maxSamples ) {                    // 欠载：保持上一采样，避免咔哒声
    out[ n++ ] = gLastSample;
  }
  return maxSamples;
}

int nes_sample_rate( void ) { return gSampleRate; }

} // extern "C"
