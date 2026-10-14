require 'json'
Pod::Spec.new do |s|
  s.name = 'DawnMeshNative'
  s.version = '1.0.0'
  s.summary = 'Opus 16kHz and DawnMesh RNNoise voice enhancement.'
  s.homepage = 'https://github.com/TimeLordFang/DawnMeshIOS'
  s.license = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author = 'DawnMesh contributors'
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  opus = JSON.parse(File.read(File.join(__dir__, 'vendor/opus/sources.json'))).map { |p| "vendor/opus/#{p}" }
  s.source_files = opus + ['src/DawnMeshAudio.h', 'src/ios_audio_codec.cpp', 'src/voice_denoiser.cpp', 'src/tonal_suppressor.cpp', 'vendor/rnnoise/src/{denoise,rnn,rnnoise_pitch,rnnoise_kiss_fft,rnnoise_celt_lpc,nnet,nnet_default,parse_lpcnet_weights,rnnoise_data,rnnoise_tables}.c']
  s.public_header_files = 'src/DawnMeshAudio.h'
  s.preserve_paths = ['src/*.h', 'vendor/opus/**/*.h', 'vendor/rnnoise/**/*.h', 'vendor/opus/COPYING', 'vendor/rnnoise/COPYING']
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) OPUS_BUILD=1 USE_ALLOCA=1 HAVE_LRINTF=1 HAVE_LRINT=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/vendor/opus/include" "$(PODS_TARGET_SRCROOT)/vendor/opus" "$(PODS_TARGET_SRCROOT)/vendor/opus/celt" "$(PODS_TARGET_SRCROOT)/vendor/opus/silk" "$(PODS_TARGET_SRCROOT)/vendor/opus/silk/float" "$(PODS_TARGET_SRCROOT)/vendor/rnnoise/include" "$(PODS_TARGET_SRCROOT)/vendor/rnnoise/src"'
  }
end
