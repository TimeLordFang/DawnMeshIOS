require 'tmpdir'
require 'json'
require 'digest'
require 'pathname'
require_relative '../ios/patches/apply'

Dir.mktmpdir('dawnmesh-patch-test') do |temporary|
  root = Pathname.new(temporary)
  source = root.join('source')
  destination = root.join('destination')
  source.mkpath
  source.join('example.c').write("int value = 1;\n")
  root.join('example.patch').write(<<~PATCH)
    --- a/example.c
    +++ b/example.c
    @@ -1 +1 @@
    -int value = 1;
    +int value = 2;
  PATCH
  entry = { 'pod' => 'fixture', 'version' => '1.0', 'file' => 'example.c',
    'sha256' => Digest::SHA256.file(source.join('example.c')).hexdigest,
    'patch' => 'example.patch' }
  2.times do
    DawnMeshPodPatches.prepare(source, destination, [entry], root)
    raise 'Patch missing' unless destination.join('example.c').read == "int value = 2;\n"
    raise 'Original changed' unless source.join('example.c').read == "int value = 1;\n"
  end
  source.join('example.c').write("int upstream_changed = 3;\n")
  begin
    DawnMeshPodPatches.prepare(source, destination, [entry], root)
    raise 'Changed upstream was accepted'
  rescue RuntimeError => error
    raise unless error.message.include?('patch needs review')
  end
end
puts 'Pod patches: repeatable copies, intact originals, changed-upstream rejection passed'
