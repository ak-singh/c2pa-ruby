# frozen_string_literal: true

require 'pathname'
require 'open-uri'
require 'fileutils'

# Wrap dev-dependency requires in begin/rescue so tasks like
# update_binaries work in environments without dev gems installed
# (fresh clones, CI steps that download binaries before bundle install).

begin
  require 'bundler/gem_tasks'
rescue LoadError
  # bundler/gem_tasks not available
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # rspec not available
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
rescue LoadError
  # rubocop not available
end

# c2pa-rs version this gem ships against. Bump in lockstep with upstream
# releases. Binaries are downloaded from the matching `c2pa-v<version>`
# release on github.com/contentauth/c2pa-rs.
C2PA_VERSION = '0.67.1'

# Platforms shipped in the gem. Each entry must have a matching zip asset
# on the corresponding c2pa-rs release page.
SUPPORTED_PLATFORMS = %w[
  aarch64-apple-darwin
  x86_64-unknown-linux-gnu
].freeze

GEM_DIR = Pathname(__dir__).freeze
LIBS_DIR = GEM_DIR.join('libs').freeze

def asset_url(platform)
  release = "c2pa-v#{C2PA_VERSION}"
  "https://github.com/contentauth/c2pa-rs/releases/download/#{release}/#{release}-#{platform}.zip"
end

def lib_filename(platform)
  platform.include?('darwin') ? 'libc2pa_c.dylib' : 'libc2pa_c.so'
end

def download_archive(url, dest_path)
  headers = {}
  headers['Authorization'] = "token #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN']

  puts "→ Downloading #{File.basename(url)}"
  URI.parse(url).open(read_timeout: 60, open_timeout: 15, **headers) do |source|
    File.binwrite(dest_path, source.read)
  end
end

def extract_native_lib(archive_path, lib_name)
  require 'zip'

  Zip::File.open(archive_path) do |zip|
    entry = zip.find { |e| File.basename(e.name) == lib_name }
    raise "#{lib_name} not found inside #{archive_path}" unless entry

    dest = Pathname(Dir.mktmpdir).join(lib_name)
    entry.extract(dest.to_s)
    dest
  end
end

def fetch_platform_binary(platform, tmp)
  lib_name = lib_filename(platform)
  archive_path = File.join(tmp, "#{platform}.zip")
  target_dir = LIBS_DIR.join(platform)
  target_file = target_dir.join(lib_name)

  download_archive(asset_url(platform), archive_path)
  extracted = extract_native_lib(archive_path, lib_name)

  FileUtils.mkdir_p(target_dir)
  FileUtils.cp(extracted, target_file)

  puts "  ✓ #{target_file.relative_path_from(GEM_DIR)}"
end

# Default task runs whichever of rubocop/spec are loaded
default_tasks = []
default_tasks << :rubocop if Rake::Task.task_defined?(:rubocop)
default_tasks << :spec    if Rake::Task.task_defined?(:spec)
task default: default_tasks unless default_tasks.empty?

desc 'Run specs only (skip linting)'
task test: :spec if Rake::Task.task_defined?(:spec)

desc 'Print the native library version'
task :version do
  require 'c2pa'
  puts C2pa.version
end

desc "Download c2pa-rs v#{C2PA_VERSION} native binaries into libs/"
task :update_binaries do
  require 'tmpdir'

  Dir.mktmpdir do |tmp|
    SUPPORTED_PLATFORMS.each { |platform| fetch_platform_binary(platform, tmp) }
  end

  puts "\nDone. Run 'bundle exec rspec' to verify."
end

desc 'Remove downloaded native binaries from libs/'
task :clobber_binaries do
  SUPPORTED_PLATFORMS.each do |platform|
    target = LIBS_DIR.join(platform, lib_filename(platform))
    if target.exist?
      target.delete
      puts "Removed #{target}"
    end
  end
end

# Make `rake build` automatically refresh binaries first, so the shipped
# gem always includes the latest pinned version.
Rake::Task['build'].enhance([:update_binaries]) if Rake::Task.task_defined?(:build)
