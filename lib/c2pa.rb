# frozen_string_literal: true

require 'json'
require_relative 'c2pa/version'
require_relative 'c2pa/error'
require_relative 'c2pa/loader'
require_relative 'c2pa/ffi'
require_relative 'c2pa/reader'
require_relative 'c2pa/builder'

# Ruby bindings for the C2PA reference SDK (c2pa-rs) via the precompiled
# c2pa-c FFI layer. Ships with native binaries — no Rust toolchain required.
#
#   puts C2pa.version
#   # => "c2pa-c-ffi/0.67.1 c2pa-rs/0.67.1"
module C2pa
  class << self
    # Returns the version string of the underlying native library, identifying
    # both the c2pa-c FFI layer and the c2pa-rs version it wraps.
    #
    # @return [String]
    # @raise [C2pa::Error] if the library returns a null pointer
    def version
      ptr = API.c2pa_version
      raise C2pa::Error, 'c2pa_version returned null' if ptr.null?

      API.read_and_free_string(ptr)
    end

    # Configures library behavior from a JSON string or Hash.
    # Settings are thread-local. Common uses: disable thumbnails, control
    # auto-actions, disable remote manifest fetch.
    #
    # @param settings [String, Hash] JSON string or Hash of settings
    # @raise [C2pa::Error] if the settings are invalid
    #
    # @example
    #   C2pa.load_settings('{"verify": {"remote_manifest_fetch": false}}')
    #   C2pa.load_settings({ 'builder' => { 'thumbnail' => { 'enabled' => false } } })
    def load_settings(settings)
      json_str = settings.is_a?(Hash) ? JSON.generate(settings) : settings
      result   = API.c2pa_load_settings(json_str, 'json')
      raise C2pa::Error, "c2pa_load_settings failed: #{API.last_error}" if result != 0
    end
  end
end
