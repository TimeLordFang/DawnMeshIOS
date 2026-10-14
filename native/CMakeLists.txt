cmake_minimum_required(VERSION 3.22)
project(dawn_mesh_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(dawn_mesh_native SHARED
    src/voice_denoiser.cpp
    src/tonal_suppressor.cpp
)

add_library(rnnoise STATIC
    vendor/rnnoise/src/denoise.c
    vendor/rnnoise/src/rnn.c
    vendor/rnnoise/src/rnnoise_pitch.c
    vendor/rnnoise/src/rnnoise_kiss_fft.c
    vendor/rnnoise/src/rnnoise_celt_lpc.c
    vendor/rnnoise/src/nnet.c
    vendor/rnnoise/src/nnet_default.c
    vendor/rnnoise/src/parse_lpcnet_weights.c
    vendor/rnnoise/src/rnnoise_data.c
    vendor/rnnoise/src/rnnoise_tables.c
)
set_target_properties(rnnoise PROPERTIES POSITION_INDEPENDENT_CODE ON C_VISIBILITY_PRESET hidden)
target_include_directories(rnnoise PUBLIC vendor/rnnoise/include PRIVATE vendor/rnnoise/src)
target_compile_options(rnnoise PRIVATE -O3)
target_link_libraries(dawn_mesh_native PRIVATE rnnoise)
if(ANDROID)
    target_sources(dawn_mesh_native PRIVATE src/voice_denoiser_jni.cpp)
else()
    enable_testing()
    add_executable(voice_denoiser_test test/voice_denoiser_test.cpp)
    target_link_libraries(voice_denoiser_test PRIVATE dawn_mesh_native)
    add_test(NAME voice_denoiser COMMAND voice_denoiser_test)
endif()

target_include_directories(dawn_mesh_native PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if (MSVC)
    target_compile_options(dawn_mesh_native PRIVATE /W4 /O2)
else()
    target_compile_options(dawn_mesh_native PRIVATE -Wall -Wextra -O3 -fPIC)
endif()

# The host regression uses the exact generic codec sources compiled by the iOS pod.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/vendor/opus/sources.json" OPUS_SOURCE_JSON)
string(JSON OPUS_SOURCE_COUNT LENGTH "${OPUS_SOURCE_JSON}")
math(EXPR OPUS_LAST_INDEX "${OPUS_SOURCE_COUNT} - 1")
set(OPUS_SOURCES)
foreach(INDEX RANGE ${OPUS_LAST_INDEX})
  string(JSON OPUS_SOURCE GET "${OPUS_SOURCE_JSON}" ${INDEX})
  list(APPEND OPUS_SOURCES "vendor/opus/${OPUS_SOURCE}")
endforeach()
add_library(dawn_opus STATIC ${OPUS_SOURCES})
set_target_properties(dawn_opus PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(dawn_opus PRIVATE OPUS_BUILD USE_ALLOCA HAVE_LRINTF HAVE_LRINT)
target_include_directories(dawn_opus PUBLIC vendor/opus/include PRIVATE vendor/opus vendor/opus/celt vendor/opus/silk vendor/opus/silk/float)
target_sources(dawn_mesh_native PRIVATE src/ios_audio_codec.cpp)
target_link_libraries(dawn_mesh_native PRIVATE dawn_opus)
if(NOT ANDROID)
  add_executable(ios_codec_test test/ios_codec_test.cpp)
  target_link_libraries(ios_codec_test PRIVATE dawn_mesh_native dawn_opus)
  add_test(NAME ios_codec COMMAND ios_codec_test)
endif()
