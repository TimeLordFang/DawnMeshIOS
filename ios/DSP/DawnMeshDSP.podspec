Pod::Spec.new do |s|
  s.name = 'DawnMeshDSP'
  s.version = '1.0.0'
  s.summary = 'DawnMesh voice enhancement for the pinned WebRTC capture processor.'
  s.homepage = 'https://github.com/TimeLordFang/DawnMeshIOS'
  s.license = { :type => 'Apache-2.0', :file => '../../LICENSE' }
  s.author = 'DawnMesh contributors'
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.source_files = '*.{h,mm}'
  s.public_header_files = 'DawnMeshInternetDSP.h'
  s.dependency 'DawnMeshNative'
  s.dependency 'flutter_webrtc', '1.6.2'
  s.pod_target_xcconfig = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17' }
end
