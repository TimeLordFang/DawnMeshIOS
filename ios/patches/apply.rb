require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'

# Compile patched copies in Pods, leaving the shared pub cache untouched.
# Source hashes deliberately fail closed when an upstream package changes.
module DawnMeshPodPatches
  def self.prepare(source_directory, destination, entries, patch_directory = __dir__)
    entries.each do |entry|
      source = source_directory.join(entry.fetch('file'))
      actual = source.file? ? Digest::SHA256.file(source).hexdigest : nil
      unless actual == entry.fetch('sha256')
        raise "DawnMesh patch needs review: #{entry.fetch('pod')} #{entry.fetch('version')} " \
              "#{entry.fetch('file')} changed. See ios/patches/README.md."
      end
    end
    FileUtils.mkdir_p(destination)
    FileUtils.cp_r("#{source_directory}/.", destination.to_s)
    entries.each do |entry|
      next unless entry['patch']
      output, status = Open3.capture2e('/usr/bin/patch', '-p1', '--batch', '--fuzz=0',
        '-i', File.join(patch_directory, entry.fetch('patch')), chdir: destination.to_s)
      raise "DawnMesh patch failed: #{output}" unless status.success?
    end
  end

  def self.install(installer)
    manifest = JSON.parse(File.read(File.join(__dir__, 'manifest.json')))
    manifest.group_by { |entry| entry.fetch('pod') }.each do |pod, entries|
      target = installer.pods_project.targets.find { |item| item.name == pod }
      raise "DawnMesh patch target missing: #{pod}" unless target
      files = entries.to_h do |entry|
        matches = target.source_build_phase.files.select do |file|
          file.file_ref && File.basename(file.file_ref.path) == entry.fetch('file')
        end
        raise "DawnMesh patch source missing/ambiguous: #{pod}/#{entry.fetch('file')}" unless matches.size == 1
        [entry.fetch('file'), matches.first]
      end
      directories = files.values.map { |file| file.file_ref.real_path.realpath.dirname }.uniq
      raise "DawnMesh patch source layout changed: #{pod}" unless directories.size == 1
      destination = installer.sandbox.root.join('DawnMeshPatchedSources', pod)
      prepare(directories.first, destination, entries)
      entries.each do |entry|
        file = files.fetch(entry.fetch('file'))
        if entry['exclude_from_compile']
          # This C++ class is included by FlutterRTCAudioSink.mm; compiling it
          # separately produces an empty archive member, not a second API.
          file.remove_from_project
        else
          file.file_ref.source_tree = 'SOURCE_ROOT'
          file.file_ref.path = destination.join(entry.fetch('file')).relative_path_from(installer.sandbox.root).to_s
        end
      end
    end
  end
end
