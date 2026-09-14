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
static volatile int gRunning = 0;
static volatile int gQuitReq = 0;
static volatile int gFrameReady = 0;
static volatile unsigned int gPadBits = 0;
static char gRomPath[1024];
static char gRomBase[256];

// 音频环形缓冲（16bit mono）
#define NES_RING_SIZE 32768
static short gRing[NES_RING_SIZE];
static volatile int gRingRead = 0;
static volatile int gRingWrite = 0;
static int gSampleRate = 22050;
static int gSamplesPerSync = 735;

extern int LoadSRAM();
extern int SaveSRAM();

/*-------------------------------------------------------------------*/
/*  Palette（RGB565）                                                 */
/*-------------------------------------------------------------------*/
static const unsigned char NesPaletteRGB[ 64 ][ 3 ] =
{
  { 0x64,0x64,0x64 },{ 0x00,0x24,0x92 },{ 0x00,0x00,0x00 },{ 0x3c,0x5c,0xa2 },
  { 0xa0,0xa0,0xa0 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },{ 0x50,0x6c,0xd2 },
  { 0xff,0xff,0xff },{ 0x18,0x60,0xc8 },{ 0x00,0x00,0x00 },{ 0x78,0x94,0xf0 },
  { 0xff,0xff,0xff },{ 0x4c,0x9c,0xec },{ 0x00,0x00,0x00 },{ 0x98,0xb8,0xf8 },
  { 0xc8,0xd4,0xe8 },{ 0x38,0x80,0xc0 },{ 0x00,0x2c,0x50 },{ 0x14,0x40,0x9c },
  { 0xec,0xec,0xec },{ 0x38,0x74,0xcc },{ 0x00,0x00,0x00 },{ 0x2c,0x6b,0xc8 },
  { 0xff,0xff,0xff },{ 0x8c,0xd8,0xf8 },{ 0x00,0x00,0x00 },{ 0x60,0xa4,0xe8 },
  { 0xff,0xff,0xff },{ 0xd8,0xf4,0xff },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0x50,0xb8,0x64 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0x70,0xcc,0x3c },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0x94,0xe0,0x88 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0xc0,0xf0,0xc0 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0xf0,0xbc,0x3c },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0xf0,0xc8,0x80 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0xf8,0xd8,0x98 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
  { 0xff,0xff,0xff },{ 0xfc,0xfc,0xb0 },{ 0x00,0x00,0x00 },{ 0x00,0x00,0x00 },
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

/* 每帧回调：标记帧就绪（Swift 端 CADisplayLink 拉取） */
void InfoNES_LoadFrame() {
  gFrameReady = 1;
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
  InfoNES_Init();
  if ( InfoNES_Load( gRomPath ) != 0 ) {
    InfoNES_Fin();
    return -1;
  }
  LoadSRAM();
  gQuitReq = 0;
  gRunning = 1;
  pthread_create( &gNesThread, NULL, NesThreadFunc, NULL );
  pthread_detach( gNesThread );
  return 0;
}

void nes_stop( void ) {
  if ( !gRunning ) return;
  gQuitReq = 1;
  // 主循环里 Menu 每帧被询问，几十 ms 内退出
  int wait = 0;
  while ( gRunning && wait < 100 ) { usleep( 10000 ); wait++; }
  SaveSRAM();
  InfoNES_Fin();
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

// 拷贝当前帧（RGB565 256x240），返回像素数
int nes_frame_copy( unsigned short *out ) {
  memcpy( out, WorkFrame, sizeof( WorkFrame ) );
  return NES_DISP_WIDTH * NES_DISP_HEIGHT;
}

// 音频拉流：返回实际样本数
int nes_audio_pull( short *out, int maxSamples ) {
  int n = 0;
  while ( gRingRead != gRingWrite && n < maxSamples ) {
    out[ n++ ] = gRing[ gRingRead ];
    gRingRead = ( gRingRead + 1 ) % NES_RING_SIZE;
  }
  // 欠载时补零（避免爆音）
  for ( ; n < maxSamples && n < 32; n++ ) out[ n ] = 0;
  return n;
}

int nes_sample_rate( void ) { return gSampleRate; }

} // extern "C"
