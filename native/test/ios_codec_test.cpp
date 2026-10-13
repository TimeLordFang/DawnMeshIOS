#include "DawnMeshAudio.h"
#include <opus.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>
int main(int argc, char** argv) {
  void* encoder = dm_encoder_create(24000);
  void* decoder = dm_decoder_create();
  assert(encoder && decoder);
  std::vector<int16_t> pcm(320), decoded(320);
  std::vector<uint8_t> packet(512);
  for (int i=0;i<320;++i) pcm[i] = static_cast<int16_t>(std::sin(i*0.13)*12000);
  int length = dm_encode(encoder, pcm.data(), 320, packet.data(), 512);
  assert(length > 0 && length <= 512);
  assert(opus_packet_get_nb_samples(packet.data(), length, 16000) == 320);
  assert(dm_decode(decoder, packet.data(), length, decoded.data(), 320) == 320);
  assert(dm_decode(decoder, nullptr, 0, decoded.data(), 320) == 320);
  assert(dm_encode(encoder, pcm.data(), 160, packet.data(), 512) < 0);
  assert(dm_decode(decoder, packet.data(), length, decoded.data(), 160) < 0);
  int error = 0;
  auto* external = opus_encoder_create(16000, 1, OPUS_APPLICATION_VOIP, &error);
  length = opus_encode(external, pcm.data(), 160, packet.data(), 512);
  assert(dm_decode(decoder, packet.data(), length, decoded.data(), 320) < 0);
  opus_encoder_destroy(external);
  // Optional Android Concentus fixture. This is an actual Android codec packet.
  if (argc > 1) {
    FILE* file = std::fopen(argv[1], "rb"); assert(file);
    length = static_cast<int>(std::fread(packet.data(), 1, 512, file)); std::fclose(file);
    assert(dm_decode(decoder, packet.data(), length, decoded.data(), 320) == 320);
  }
  if (argc > 2) {
    FILE* file = std::fopen(argv[2], "wb"); assert(file);
    length = dm_encode(encoder, pcm.data(), 320, packet.data(), 512);
    std::fwrite(packet.data(), 1, length, file); std::fclose(file);
  }
  void* denoiser = dm_denoiser_create(16000); assert(denoiser);
  assert(dm_denoise(denoiser, pcm.data(), 320, 1));
  dm_denoiser_free(denoiser); dm_encoder_free(encoder); dm_decoder_free(decoder);
  std::puts("Opus 16kHz/20ms, PLC, malformed lengths and RNNoise passed");
}
