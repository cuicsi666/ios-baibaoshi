#ifndef NES_BRIDGE_H
#define NES_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int  nes_start(const char *romPath);
void nes_stop(void);
int  nes_running(void);
void nes_set_pad(uint32_t bits);
int  nes_frame_ready(void);
int  nes_frame_copy(uint16_t *out);
int  nes_audio_pull(int16_t *out, int maxSamples);
int  nes_sample_rate(void);
void nes_set_sav_dir(const char *dir);

#ifdef __cplusplus
}
#endif

#endif /* NES_BRIDGE_H */
