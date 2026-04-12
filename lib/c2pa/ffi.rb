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
    REQUIRED_FUNCTIONS = %w[
      c2pa_version
      c2pa_error
      c2pa_string_free
      c2pa_create_stream
      c2pa_release_stream
      c2pa_reader_from_stream
      c2pa_reader_json
      c2pa_reader_detailed_json
      c2pa_reader_is_embedded
      c2pa_reader_remote_url
      c2pa_reader_free
      c2pa_signer_from_info
      c2pa_signer_free
      c2pa_builder_from_json
      c2pa_builder_add_action
      c2pa_builder_sign
      c2pa_builder_free
      c2pa_manifest_bytes_free
    ].freeze

    missing = REQUIRED_FUNCTIONS.reject { |fn| ffi_libraries.first.find_function(fn) }
    unless missing.empty?
      raise C2pa::LibraryNotFoundError,
            "Native library is missing required symbols: #{missing.join(', ')}. " \
            'The library may be an incompatible version.'
    end

    attach_function :c2pa_version, [], :pointer
    attach_function :c2pa_error, [], :pointer
    attach_function :c2pa_string_free, [:pointer], :void

    # Stream callbacks — stored as instance variables in Stream to prevent GC
    callback :read_callback,  %i[pointer pointer ssize_t], :ssize_t
    callback :seek_callback,  %i[pointer ssize_t int],     :ssize_t
    callback :write_callback, %i[pointer pointer ssize_t], :ssize_t
    callback :flush_callback, [:pointer],                  :ssize_t

    attach_function :c2pa_create_stream,
                    %i[pointer read_callback seek_callback write_callback flush_callback],
                    :pointer
    attach_function :c2pa_release_stream, [:pointer], :void

    attach_function :c2pa_reader_from_stream,   %i[string pointer], :pointer
    attach_function :c2pa_reader_json,          [:pointer],         :pointer
    attach_function :c2pa_reader_detailed_json, [:pointer],         :pointer
    attach_function :c2pa_reader_is_embedded,   [:pointer],         :int
    attach_function :c2pa_reader_remote_url,    [:pointer],         :pointer
    attach_function :c2pa_reader_free,          [:pointer],         :void

    # Signer — wraps a cert + private key + algorithm into an opaque signer handle
    attach_function :c2pa_signer_from_info, [:pointer], :pointer
    attach_function :c2pa_signer_free,      [:pointer], :void

    # Builder — creates and signs manifests
    attach_function :c2pa_builder_from_json, [:string], :pointer
    attach_function :c2pa_builder_add_action,  %i[pointer string], :int
    attach_function :c2pa_builder_sign,        %i[pointer string pointer pointer pointer pointer], :int64
    attach_function :c2pa_builder_free,        [:pointer],                             :void
    attach_function :c2pa_manifest_bytes_free, [:pointer],                             :void

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
