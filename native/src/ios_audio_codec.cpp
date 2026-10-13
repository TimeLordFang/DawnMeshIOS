#include "DawnMeshAudio.h"
#include "voice_denoiser.h"
#include <opus.h>
#include <new>
extern "C" {
void* dm_encoder_create(int bitrate) {
  int error = 0;
  auto* encoder = opus_encoder_create(16000, 1, OPUS_APPLICATION_VOIP, &error);
  if (!encoder || error != OPUS_OK) return nullptr;
  opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
  opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(5));
  opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
  opus_encoder_ctl(encoder, OPUS_SET_VBR(1));
  opus_encoder_ctl(encoder, OPUS_SET_VBR_CONSTRAINT(1));
  opus_encoder_ctl(encoder, OPUS_SET_DTX(1));
  return encoder;
}
void dm_encoder_free(void* encoder) { if (encoder) opus_encoder_destroy(static_cast<OpusEncoder*>(encoder)); }
int dm_encoder_bitrate(void* encoder, int bitrate) {
  return encoder ? opus_encoder_ctl(static_cast<OpusEncoder*>(encoder), OPUS_SET_BITRATE(bitrate)) : OPUS_BAD_ARG;
}
int dm_encode(void* encoder, const int16_t* pcm, int count, uint8_t* out, int capacity) {
  if (!encoder || !pcm || !out || count != 320 || capacity < 1) return OPUS_BAD_ARG;
  return opus_encode(static_cast<OpusEncoder*>(encoder), pcm, count, out, capacity);
}
void* dm_decoder_create() {
  int error = 0;
  return opus_decoder_create(16000, 1, &error);
}
void dm_decoder_free(void* decoder) { if (decoder) opus_decoder_destroy(static_cast<OpusDecoder*>(decoder)); }
int dm_decode(void* decoder, const uint8_t* data, int length, int16_t* pcm, int capacity) {
  if (!decoder || !pcm || capacity < 320 || length < 0 || (length && !data)) return OPUS_BAD_ARG;
  if (length && opus_packet_get_nb_samples(data, length, 16000) != 320) return OPUS_BAD_ARG;
  return opus_decode(static_cast<OpusDecoder*>(decoder), data, length, pcm, 320, 0);
}
void* dm_denoiser_create(int rate) {
  if (rate != 16000 && rate != 32000 && rate != 48000) return nullptr;
  return new (std::nothrow) dawnmesh::VoiceDenoiser(rate);
}
void dm_denoiser_free(void* denoiser) { delete static_cast<dawnmesh::VoiceDenoiser*>(denoiser); }
int dm_denoise(void* denoiser, int16_t* pcm, int count, int level) {
  return denoiser && pcm && static_cast<dawnmesh::VoiceDenoiser*>(denoiser)->processPcm(pcm, count, level);
}
int dm_denoise_float(void* denoiser, float* pcm, int count, int level) {
  return denoiser && pcm && static_cast<dawnmesh::VoiceDenoiser*>(denoiser)->processFloat(pcm, count, level);
}
}
