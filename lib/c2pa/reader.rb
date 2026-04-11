# frozen_string_literal: true

module C2pa
  # Internal bridge between a Ruby IO object and the C2paStream struct.
  #
  # The C library holds raw function pointers for the duration of a read or
  # sign operation. Ruby's GC must not move or collect those closures while
  # C holds them. Storing each callback as an instance variable on this object
  # pins it for the lifetime of the Stream instance.
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

  # High-level Ruby wrapper around the C2PA Reader API.
  #
  # Reads C2PA manifests from any IO-like object (File, StringIO, etc.)
  # without materialising the entire file into a Ruby string.
  #
  # @example Block form (recommended)
  #   C2pa::Reader.open('image/jpeg', File.open('photo.jpg', 'rb')) do |r|
  #     puts r.json
  #   end
  #
  # @example Manual lifecycle
  #   reader = C2pa::Reader.open('image/jpeg', io)
  #   puts reader.json
  #   reader.close
  class Reader
    # @param mime_type [String] MIME type of the asset, e.g. "image/jpeg"
    # @param io       [IO]     readable, seekable IO object
    # @yieldparam reader [C2pa::Reader]
    # @return [C2pa::Reader, Object] reader instance, or block return value
    def self.open(mime_type, io)
      reader = new(mime_type, io)
      return reader unless block_given?

      begin
        yield reader
      ensure
        reader.close
      end
    end

    def initialize(mime_type, io)
      @closed = false
      @ptr    = FFI::Pointer::NULL # safe sentinel so close is always callable
      @stream = Stream.new(io)
      @ptr    = API.c2pa_reader_from_stream(mime_type, @stream.ptr)

      return unless @ptr.null?

      # Capture error before @stream.close — any C call can overwrite the slot.
      error_msg = API.last_error
      @stream.close
      raise C2pa::Error, "c2pa_reader_from_stream failed: #{error_msg}"
    end

    # Returns the manifest store as a JSON string.
    # @return [String]
    def json
      check_open!
      ptr = API.c2pa_reader_json(@ptr)
      raise C2pa::Error, "c2pa_reader_json failed: #{API.last_error}" if ptr.null?

      API.read_and_free_string(ptr)
    end

    # Returns the detailed manifest store as a JSON string (includes ingredient details).
    # @return [String]
    def detailed_json
      check_open!
      ptr = API.c2pa_reader_detailed_json(@ptr)
      raise C2pa::Error, "c2pa_reader_detailed_json failed: #{API.last_error}" if ptr.null?

      API.read_and_free_string(ptr)
    end

    # Returns true if the manifest is embedded in the asset.
    # @return [Boolean]
    def embedded?
      check_open!
      API.c2pa_reader_is_embedded(@ptr) != 0
    end

    # Returns the remote URL of the manifest, or nil if there is none.
    # @return [String, nil]
    def remote_url
      check_open!
      ptr = API.c2pa_reader_remote_url(@ptr)
      return nil if ptr.null?

      API.read_and_free_string(ptr)
    end

    # Release native resources. Idempotent — safe to call more than once.
    def close
      return if @closed

      @closed = true
      API.c2pa_reader_free(@ptr) unless @ptr.null?
      @stream&.close
    end

    # @return [Boolean]
    def closed?
      @closed
    end

    private

    def check_open!
      raise C2pa::ClosedError, 'Reader' if @closed
    end
  end
end
