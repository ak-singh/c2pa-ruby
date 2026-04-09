# frozen_string_literal: true

require 'ffi'
require_relative 'loader'
require_relative 'error'

module C2pa
  # Raw FFI bindings to the C2PA native library (libc2pa_c).
  #
  # Strings returned by the C library (char*) MUST be freed with
  # c2pa_string_free. Never free twice.
  module API
    extend FFI::Library

    begin
      ffi_lib C2pa::Loader.library_path
    rescue LoadError => e
      raise C2pa::LibraryNotFoundError, "Failed to load native library: #{e.message}"
    end

    # Required symbols validated against the raw library object BEFORE attach_function,
    # mirroring the Python SDK's _validate_library_exports pattern. Running before
    # attach_function means we control the error message — otherwise FFI raises its own
    # FFI::NotFoundError with no context about version compatibility.
    REQUIRED_FUNCTIONS = %w[c2pa_version c2pa_error c2pa_string_free].freeze

    missing = REQUIRED_FUNCTIONS.reject { |fn| ffi_libraries.first.find_function(fn) }
    unless missing.empty?
      raise C2pa::LibraryNotFoundError,
            "Native library is missing required symbols: #{missing.join(', ')}. " \
            'The library may be an incompatible version.'
    end

    attach_function :c2pa_version, [], :pointer
    attach_function :c2pa_error, [], :pointer
    attach_function :c2pa_string_free, [:pointer], :void

    def self.last_error
      ptr = c2pa_error
      return nil if ptr.null?

      msg = _read_and_free(ptr)
      msg.empty? ? nil : msg
    end

    def self.read_and_free_string(ptr)
      return nil if ptr.null?

      _read_and_free(ptr)
    end

    # Reads a C string, validates UTF-8, frees the pointer, and returns the string.
    # Raises C2pa::Error if the bytes are not valid UTF-8 — consistent with the
    # Python SDK's decode('utf-8', errors='strict') behaviour.
    def self._read_and_free(ptr)
      raw = ptr.read_string
      c2pa_string_free(ptr)
      str = raw.force_encoding('UTF-8')
      raise C2pa::Error, 'Native library returned invalid UTF-8' unless str.valid_encoding?

      str
    end
    private_class_method :_read_and_free
  end
end
