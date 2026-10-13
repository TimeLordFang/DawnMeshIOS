#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void* dm_encoder_create(int bitrate);
void dm_encoder_free(void* encoder);
int dm_encoder_bitrate(void* encoder, int bitrate);
int dm_encode(void* encoder, const int16_t* pcm, int count, uint8_t* out, int capacity);
void* dm_decoder_create(void);
void dm_decoder_free(void* decoder);
int dm_decode(void* decoder, const uint8_t* data, int length, int16_t* pcm, int capacity);
void* dm_denoiser_create(int rate);
void dm_denoiser_free(void* denoiser);
int dm_denoise(void* denoiser, int16_t* pcm, int count, int level);
int dm_denoise_float(void* denoiser, float* pcm, int count, int level);
#ifdef __cplusplus
}
#endif
