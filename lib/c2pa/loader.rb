# frozen_string_literal: true

require 'rbconfig'

module C2pa
  # Resolves the path to the precompiled native library bundled with this gem.
  #
  # Resolution order:
  #   1. C2PA_LIBRARY_PATH env var — full path to the library file
  #   2. Bundled library under gems/libs/<platform>/libc2pa_c.<ext>
  module Loader
    GEM_ROOT = File.expand_path('../..', __dir__)

    PLATFORM_MAP = {
      # host_cpu returns 'arm64' on Apple Silicon; 'aarch64' is the conventional
      # triple name used for the libs/ directory.
      /arm64.*darwin|aarch64.*darwin/ => 'aarch64-apple-darwin',
      /x86_64.*darwin/ => 'x86_64-apple-darwin',
      /x86_64.*linux/ => 'x86_64-unknown-linux-gnu'
    }.freeze

    LIB_NAMES = {
      'darwin' => 'libc2pa_c.dylib',
      'linux' => 'libc2pa_c.so'
    }.freeze

    class << self
      # @return [String] absolute path to the native library
      # @raise [C2pa::LibraryNotFoundError]
      def library_path
        if (env_path = ENV.fetch('C2PA_LIBRARY_PATH', nil))
          return env_path if File.exist?(env_path)

          raise C2pa::LibraryNotFoundError,
                "C2PA_LIBRARY_PATH='#{env_path}' does not exist."
        end

        platform = detect_platform
        lib_name = detect_lib_name
        path = File.join(GEM_ROOT, 'libs', platform, lib_name)
        return path if File.exist?(path)

        raise C2pa::LibraryNotFoundError,
              "Native library not found for platform '#{platform}' at '#{path}'. " \
              'Set C2PA_LIBRARY_PATH to specify a custom path.'
      end

      private

      def detect_platform
        host = "#{RbConfig::CONFIG['host_cpu']}-#{RbConfig::CONFIG['host_os']}"
        PLATFORM_MAP.each { |pattern, name| return name if host.match?(pattern) }
        raise C2pa::LibraryNotFoundError,
              "Unsupported platform: '#{host}'. " \
              'Supported: aarch64-apple-darwin, x86_64-apple-darwin, x86_64-unknown-linux-gnu.'
      end

      def detect_lib_name
        os = RbConfig::CONFIG['host_os'].to_s
        return LIB_NAMES['darwin'] if os.include?('darwin')
        return LIB_NAMES['linux']  if os.include?('linux')

        raise C2pa::LibraryNotFoundError, "Unsupported OS: '#{os}'"
      end
    end
  end
end
