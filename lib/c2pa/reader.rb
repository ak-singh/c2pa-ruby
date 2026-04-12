# frozen_string_literal: true

require 'json'

module C2pa
  # Bridges a Ruby IO object to the C2paStream callback interface.
  # Callbacks are stored as instance variables to prevent GC collection
  # while the C library holds function pointers to them.
  #
  # @api private
  class Stream
    attr_reader :ptr

    def initialize(io)
      @io = io
      @read_cb  = build_read_cb
      @seek_cb  = build_seek_cb
      @write_cb = build_write_cb
      @flush_cb = build_flush_cb

      @ptr = API.c2pa_create_stream(nil, @read_cb, @seek_cb, @write_cb, @flush_cb)
      raise C2pa::Error, "c2pa_create_stream returned null: #{API.last_error}" if @ptr.null?
    end

    def close
      return if @ptr.nil? || @ptr.null?

      API.c2pa_release_stream(@ptr)
      @ptr = nil
    end

    private

    def build_read_cb
      FFI::Function.new(:ssize_t, %i[pointer pointer ssize_t]) do |_ctx, buf, len|
        bytes = @io.read(len)
        # nil  → EOF (IO#read returns nil when at end of file)
        # ""   → EOF on some IO implementations that return empty string instead of nil
        next 0 if bytes.nil? || bytes.empty?

        actual = [bytes.bytesize, len].min
        buf.put_bytes(0, bytes, 0, actual)
        actual
      rescue StandardError
        -1
      end
    end

    def build_seek_cb
      FFI::Function.new(:ssize_t, %i[pointer ssize_t int]) do |_ctx, offset, whence|
        @io.seek(offset, whence)
        @io.tell
      rescue StandardError
        -1
      end
    end

    def build_write_cb
      FFI::Function.new(:ssize_t, %i[pointer pointer ssize_t]) do |_ctx, buf, len|
        @io.write(buf.read_bytes(len))
        len
      rescue StandardError
        -1
      end
    end

    def build_flush_cb
      FFI::Function.new(:ssize_t, [:pointer]) do |_ctx|
        @io.flush
        0
      rescue StandardError
        -1
      end
    end
  end

  # Reads C2PA manifests from any IO-like object (File, StringIO, etc.).
  # Not thread-safe — do not share across threads.
  #
  # @example
  #   C2pa::Reader.open('image/jpeg', File.open('photo.jpg', 'rb')) do |r|
  #     puts r.json
  #   end
  class Reader # rubocop:disable Metrics/ClassLength
    # Returns the MIME types supported by the reader.
    # @return [Array<String>]
    def self.supported_mime_types
      count_ptr = FFI::MemoryPointer.new(:size_t)
      ptr       = API.c2pa_reader_supported_mime_types(count_ptr)
      API.read_and_free_string_array(ptr, count_ptr)
    end

    # @param mime_type      [String]      e.g. "image/jpeg"
    # @param io             [IO]          readable, seekable
    # @param manifest_bytes [String, nil] raw manifest bytes returned by {Builder#sign};
    #   pass when the asset has no embedded manifest (signed with {Builder#set_no_embed})
    # @yieldparam reader [C2pa::Reader]
    def self.open(mime_type, io, manifest_bytes = nil)
      reader = new(mime_type, io, manifest_bytes)
      return reader unless block_given?

      begin
        yield reader
      ensure
        reader.close
      end
    end

    def initialize(mime_type, io, manifest_bytes = nil) # rubocop:disable Metrics/AbcSize
      raise TypeError, 'manifest_bytes must be a String' if manifest_bytes && !manifest_bytes.is_a?(String)

      @closed = false
      @ptr    = FFI::Pointer::NULL
      @stream = Stream.new(io)
      @ptr    = if manifest_bytes
                  data_ptr = FFI::MemoryPointer.new(:uint8, [manifest_bytes.bytesize, 1].max)
                  data_ptr.put_bytes(0, manifest_bytes)
                  API.c2pa_reader_from_manifest_data_and_stream(mime_type, @stream.ptr, data_ptr,
                                                                manifest_bytes.bytesize)
                else
                  API.c2pa_reader_from_stream(mime_type, @stream.ptr)
                end

      return unless @ptr.null?

      # Capture error before @stream.close — any C call can overwrite the slot.
      error_msg = API.last_error
      @stream.close
      fn = manifest_bytes ? 'c2pa_reader_from_manifest_data_and_stream' : 'c2pa_reader_from_stream'
      raise C2pa::Error, "#{fn} failed: #{error_msg}"
    end

    # @return [String] manifest store as JSON
    def json
      check_open!
      ptr = API.c2pa_reader_json(@ptr)
      raise C2pa::Error, "c2pa_reader_json failed: #{API.last_error}" if ptr.null?

      API.read_and_free_string(ptr)
    end

    # @return [String] manifest store as JSON, including ingredient details
    def detailed_json
      check_open!
      ptr = API.c2pa_reader_detailed_json(@ptr)
      raise C2pa::Error, "c2pa_reader_detailed_json failed: #{API.last_error}" if ptr.null?

      API.read_and_free_string(ptr)
    end

    def embedded?
      check_open!
      API.c2pa_reader_is_embedded(@ptr) != 0
    end

    # @return [Hash, nil] the active manifest as a parsed Hash, or nil if none
    def active_manifest
      check_open!
      data = manifest_store
      return nil unless data&.key?('active_manifest')

      data['manifests']&.fetch(data['active_manifest'], nil)
    end

    # @param label [String] manifest label
    # @return [Hash, nil] the manifest for the given label, or nil if not found
    def manifest(label)
      check_open!
      manifest_store&.dig('manifests', label)
    end

    # @return [String, nil] overall validation state (e.g. "Valid", "Invalid"), or nil if absent
    def validation_state
      check_open!
      manifest_store&.[]('validation_state')
    end

    # @return [Hash, nil] detailed validation results, or nil if absent
    def validation_results
      check_open!
      manifest_store&.[]('validation_results')
    end

    # Writes an embedded resource (e.g. thumbnail) to dest_io.
    #
    # @param uri     [String] resource identifier as it appears in the manifest
    # @param dest_io [IO]     writable stream
    # @return [Integer] number of bytes written
    # @raise [C2pa::Error] if the resource is not found or write fails
    def resource_to_stream(uri, dest_io)
      check_open!
      stream = nil
      begin
        stream = Stream.new(dest_io)
        result = API.c2pa_reader_resource_to_stream(@ptr, uri, stream.ptr)
        raise C2pa::Error, "c2pa_reader_resource_to_stream failed: #{API.last_error}" if result.negative?

        result
      ensure
        stream&.close
      end
    end

    # @return [String, nil] remote manifest URL, or nil if embedded
    def remote_url
      check_open!
      ptr = API.c2pa_reader_remote_url(@ptr)
      return nil if ptr.null?

      API.read_and_free_string(ptr)
    end

    # Idempotent.
    def close
      return if @closed

      @closed = true
      API.c2pa_reader_free(@ptr) unless @ptr.null?
      @stream&.close
    end

    def closed?
      @closed
    end

    private

    # Parses and caches the manifest store JSON.
    def manifest_store
      return @manifest_store if defined?(@manifest_store)

      @manifest_store = JSON.parse(json)
    end

    def check_open!
      raise C2pa::ClosedError, 'Reader' if @closed
    end
  end
end
