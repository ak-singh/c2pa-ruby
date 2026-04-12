# frozen_string_literal: true

require 'json'

module C2pa
  # Wraps a native C2PA signer (cert + private key + algorithm).
  # Not thread-safe — do not share across threads.
  #
  # @example
  #   signer = C2pa::Signer.from_info(
  #     alg:  'es256',
  #     cert: File.read('es256_certs.pem'),
  #     key:  File.read('es256_private.key')
  #   )
  #   signer.close
  class Signer
    # @param alg    [String] signing algorithm — "es256", "es384", "es512",
    #                        "ps256", "ps384", "ps512", or "ed25519"
    # @param cert   [String] PEM certificate chain
    # @param key    [String] PEM private key
    # @param ta_url [String, nil] RFC 3161 timestamp authority URL;
    #               omit to sign without a timestamp
    # @raise [C2pa::Error] if the algorithm or private key is invalid
    def self.from_info(alg:, cert:, key:, ta_url: nil)
      struct_mem, pins = build_signer_info(alg, cert, key, ta_url)
      signer_ptr = API.c2pa_signer_from_info(struct_mem)
      GC.keep_alive(*pins) if GC.respond_to?(:keep_alive) # Ruby 3.3+
      raise C2pa::Error, "c2pa_signer_from_info failed: #{API.last_error}" if signer_ptr.null?

      new(signer_ptr)
    end

    # Builds the C2paSignerInfo struct layout (four char* fields) manually.
    # FFI::Struct does not allow setting :string fields, so we use raw pointers.
    # Returns [mem, pins]; caller keeps pins alive for the duration of the C call.
    #
    # @api private
    def self.build_signer_info(alg, cert, key, ta_url)
      ptr_size = FFI::Pointer::SIZE
      alg_ptr  = FFI::MemoryPointer.from_string(alg)
      cert_ptr = FFI::MemoryPointer.from_string(cert)
      key_ptr  = FFI::MemoryPointer.from_string(key)
      ta_ptr   = ta_url ? FFI::MemoryPointer.from_string(ta_url) : FFI::Pointer::NULL
      mem      = FFI::MemoryPointer.new(:pointer, 4)
      mem.put_pointer(0 * ptr_size, alg_ptr)
      mem.put_pointer(1 * ptr_size, cert_ptr)
      mem.put_pointer(2 * ptr_size, key_ptr)
      mem.put_pointer(3 * ptr_size, ta_ptr)
      [mem, [alg_ptr, cert_ptr, key_ptr, ta_ptr]]
    end
    private_class_method :build_signer_info

    # @api private
    def initialize(ptr)
      @ptr    = ptr
      @closed = false
    end

    # Idempotent.
    def close
      return if @closed

      @closed = true
      API.c2pa_signer_free(@ptr)
    end

    def closed?
      @closed
    end

    # Returns the signature buffer size needed for pre-allocation.
    # @return [Integer]
    def reserve_size
      check_open!
      API.c2pa_signer_reserve_size(@ptr)
    end

    # @api private
    attr_reader :ptr

    private

    def check_open!
      raise C2pa::ClosedError, 'Signer' if @closed
    end
  end

  # Builds and signs C2PA manifests.
  # Not thread-safe — do not share across threads.
  #
  # @example
  #   signer  = C2pa::Signer.from_info(alg: 'es256', cert: cert_pem, key: key_pem)
  #   builder = C2pa::Builder.from_manifest('{"claim_generator":"my-app/1.0","assertions":[]}')
  #   builder.add_action('c2pa.published')
  #
  #   File.open('input.jpg', 'rb') do |src|
  #     File.open('output.jpg', 'wb') do |dst|
  #       builder.sign(signer, 'image/jpeg', src, dst)
  #     end
  #   end
  #
  #   signer.close
  #   builder.close
  class Builder # rubocop:disable Metrics/ClassLength
    # Returns the MIME types supported by the builder.
    # @return [Array<String>]
    def self.supported_mime_types
      count_ptr = FFI::MemoryPointer.new(:size_t)
      ptr       = API.c2pa_builder_supported_mime_types(count_ptr)
      API.read_and_free_string_array(ptr, count_ptr)
    end

    # @param manifest [String, Hash] manifest definition — Hash or JSON string
    # @return [C2pa::Builder]
    # @raise [C2pa::Error] if the JSON is invalid
    def self.from_manifest(manifest)
      json_str = manifest.is_a?(Hash) ? JSON.generate(manifest) : manifest
      ptr = API.c2pa_builder_from_json(json_str)
      raise C2pa::Error, "c2pa_builder_from_json failed: #{API.last_error}" if ptr.null?

      new(ptr)
    end

    # Restores a Builder from an archive written by {#to_archive}.
    #
    # @param archive_io [IO] readable, seekable
    # @return [C2pa::Builder]
    # @raise [C2pa::Error] if the archive is invalid
    def self.from_archive(archive_io)
      stream    = nil
      ptr       = FFI::Pointer::NULL
      error_msg = nil
      begin
        stream    = Stream.new(archive_io)
        ptr       = API.c2pa_builder_from_archive(stream.ptr)
        error_msg = API.last_error if ptr.null?
      ensure
        stream&.close
      end
      raise C2pa::Error, "c2pa_builder_from_archive failed: #{error_msg}" if ptr.null?

      new(ptr)
    end

    private_class_method :new

    # Sets the remote URL where the manifest will be hosted.
    # Combine with {#set_no_embed} to omit the manifest from the asset entirely.
    #
    # @param url [String] remote manifest URL
    # @raise [C2pa::Error] if the URL is invalid
    def set_remote_url(url) # rubocop:disable Naming/AccessorMethodName
      check_open!
      result = API.c2pa_builder_set_remote_url(@ptr, url)
      raise C2pa::Error, "c2pa_builder_set_remote_url failed: #{API.last_error}" if result != 0
    end

    # Prevents the manifest from being embedded in the asset.
    # The manifest bytes returned by {#sign} can then be hosted externally.
    def set_no_embed
      check_open!
      API.c2pa_builder_set_no_embed(@ptr)
    end

    # Appends an action. Multiple calls accumulate into a single c2pa.actions assertion.
    #
    # @param action_json [String, Hash] bare label ("c2pa.published"),
    #   Hash ({ "action" => "c2pa.edited" }), or pre-serialized JSON string
    # @raise [C2pa::Error] if the action is invalid
    def add_action(action_json)
      check_open!

      # Accept a bare label string as shorthand for { "action": "..." }
      action_json = { 'action' => action_json } if action_json.is_a?(String) && !action_json.start_with?('{')
      json_str    = action_json.is_a?(Hash) ? JSON.generate(action_json) : action_json

      result = API.c2pa_builder_add_action(@ptr, json_str)
      raise C2pa::Error, "c2pa_builder_add_action failed: #{API.last_error}" if result != 0
    end

    # Attaches an ingredient to the manifest.
    #
    # @param ingredient_json [String, Hash] ingredient definition
    # @param mime_type       [String] e.g. "image/jpeg"
    # @param source_io       [IO]     readable, seekable
    # @raise [C2pa::Error] if the ingredient is invalid
    def add_ingredient(ingredient_json, mime_type, source_io)
      check_open!

      json_str = ingredient_json.is_a?(Hash) ? JSON.generate(ingredient_json) : ingredient_json

      stream = nil
      begin
        stream = Stream.new(source_io)
        result = API.c2pa_builder_add_ingredient_from_stream(@ptr, json_str, mime_type, stream.ptr)
        raise C2pa::Error, "c2pa_builder_add_ingredient_from_stream failed: #{API.last_error}" if result != 0
      ensure
        stream&.close
      end
    end

    # Attaches a binary resource to the manifest, identified by URI.
    # Useful for thumbnails, icons, or custom data referenced from assertions.
    #
    # @param uri       [String] resource identifier (e.g. "thumbnail")
    # @param source_io [IO]    readable, seekable
    # @raise [C2pa::Error] if the resource cannot be added
    def add_resource(uri, source_io)
      check_open!

      stream = nil
      begin
        stream = Stream.new(source_io)
        result = API.c2pa_builder_add_resource(@ptr, uri, stream.ptr)
        raise C2pa::Error, "c2pa_builder_add_resource failed: #{API.last_error}" if result != 0
      ensure
        stream&.close
      end
    end

    # Serializes builder state (ingredient hashes + manifest template) to an archive.
    # Restore with {Builder.from_archive}.
    #
    # @param dest_io [IO] writable, seekable
    # @raise [C2pa::Error] if serialization fails
    def to_archive(dest_io)
      check_open!

      stream = nil
      begin
        stream = Stream.new(dest_io)
        result = API.c2pa_builder_to_archive(@ptr, stream.ptr)
        raise C2pa::Error, "c2pa_builder_to_archive failed: #{API.last_error}" if result != 0
      ensure
        stream&.close
      end
    end

    # Signs the source asset and writes the signed output to dest_io.
    #
    # @param signer    [C2pa::Signer]
    # @param mime_type [String] e.g. "image/jpeg"
    # @param source_io [IO]     readable, seekable
    # @param dest_io   [IO]     writable, seekable
    # @return [String] raw manifest bytes embedded in the output
    # @raise [C2pa::Error] if signing fails
    def sign(signer, mime_type, source_io, dest_io)
      check_open!
      raise C2pa::ClosedError, 'Signer' if signer.closed?

      source_stream      = nil
      dest_stream        = nil
      manifest_bytes_ptr = FFI::MemoryPointer.new(:pointer)

      result = -1
      begin
        source_stream = Stream.new(source_io)
        dest_stream   = Stream.new(dest_io)
        result        = call_sign(signer, mime_type, source_stream, dest_stream, manifest_bytes_ptr)
        error_msg     = API.last_error if result.negative? # capture before stream close overwrites it
      ensure
        dest_stream&.close
        source_stream&.close
      end

      raise C2pa::Error, "c2pa_builder_sign failed: #{error_msg}" if result.negative?

      read_manifest_bytes(manifest_bytes_ptr, result)
    end

    # Idempotent.
    def close
      return if @closed

      @closed = true
      API.c2pa_builder_free(@ptr) unless @ptr.null?
    end

    def closed?
      @closed
    end

    private

    def initialize(ptr)
      @closed = false
      @ptr    = ptr
    end

    def check_open!
      raise C2pa::ClosedError, 'Builder' if @closed
    end

    def call_sign(signer, mime_type, source_stream, dest_stream, manifest_bytes_ptr)
      API.c2pa_builder_sign(
        @ptr, mime_type,
        source_stream.ptr, dest_stream.ptr,
        signer.ptr,
        manifest_bytes_ptr
      )
    end

    def read_manifest_bytes(manifest_bytes_ptr, len)
      raw_ptr = manifest_bytes_ptr.read_pointer
      raise C2pa::Error, 'c2pa_builder_sign succeeded but manifest pointer is null' if raw_ptr.null?

      begin
        raw_ptr.read_bytes(len)
      ensure
        API.c2pa_manifest_bytes_free(raw_ptr)
      end
    end
  end
end
