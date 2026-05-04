# c2pa-ruby

Ruby bindings for the [C2PA](https://c2pa.org) reference SDK (`c2pa-rs`).

[C2PA](https://c2pa.org) (Coalition for Content Provenance and Authenticity) is an open standard for attaching cryptographically signed provenance metadata to digital media. This gem provides Ruby bindings to read, validate, and create C2PA manifests.

Ships with precompiled native binaries — **no Rust toolchain required**.

## Requirements

- Ruby 3.1 or later
- macOS (Apple Silicon or Intel) or Linux x86_64

## Installation

Add to your Gemfile:

```ruby
gem "c2pa"
```

Or install directly:

```sh
gem install c2pa
```

## Reading manifests

### Read a manifest

```ruby
require "c2pa"
require "json"

C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  data = JSON.parse(reader.json)
  puts data["manifests"].keys
end
```

The block form is recommended — the reader and all native resources are released
automatically when the block exits, even if an exception is raised.

### Access manifest data directly

```ruby
C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  puts reader.active_manifest    # Hash — the active manifest
  puts reader.validation_state   # "Valid", "Invalid", etc.
  puts reader.validation_results # Hash with detailed validation info
end
```

### Check if a manifest is embedded or remote

```ruby
C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  if reader.embedded?
    puts "Embedded manifest"
  else
    puts "Remote manifest at: #{reader.remote_url}"
  end
end
```

For assets with remote manifests, the library fetches the manifest over the
network automatically during `Reader.open`. If the network is unavailable,
`Reader.open` raises `C2pa::Error`.

### Extract an embedded resource

Resources such as thumbnails embedded in a manifest can be written to any IO:

```ruby
C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  uri = reader.active_manifest&.dig("thumbnail", "identifier")
  File.open("thumb.jpg", "wb") { |f| reader.resource_to_stream(uri, f) } if uri
end
```

### Read a sidecar (non-embedded) manifest

When an asset was signed with `set_no_embed`, pass the manifest bytes back to
`Reader.open` to read without a network call:

```ruby
manifest_bytes = File.binread("manifest.c2pa")

C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb"), manifest_bytes) do |reader|
  puts reader.json
end
```

### Read from any IO object

The reader works with any seekable IO — a file, a `StringIO`, a cloud storage
stream, etc.:

```ruby
bytes = download_from_s3("photo.jpg")
C2pa::Reader.open("image/jpeg", StringIO.new(bytes)) do |reader|
  puts reader.json
end
```

## Creating and signing manifests

### Sign an asset

```ruby
require "c2pa"

cert   = File.read("es256_certs.pem")
key    = File.read("es256_private.key")
signer = C2pa::Signer.from_info(alg: "es256", cert: cert, key: key)

manifest = {
  "claim_generator" => "my-app/1.0",
  "assertions"      => []
}

builder = C2pa::Builder.from_manifest(manifest)
builder.add_action("c2pa.published")

File.open("input.jpg", "rb") do |src|
  File.open("output.jpg", "wb") do |dst|
    builder.sign(signer, "image/jpeg", src, dst)
  end
end

signer.close
builder.close
```

### Add an ingredient

```ruby
builder = C2pa::Builder.from_manifest(manifest)

File.open("source.jpg", "rb") do |f|
  builder.add_ingredient({ "title" => "source.jpg" }, "image/jpeg", f)
end
```

### Add a resource (e.g. thumbnail)

```ruby
File.open("thumbnail.jpg", "rb") do |f|
  builder.add_resource("thumbnail", f)
end
```

### Create a remote (sidecar) manifest

Sign without embedding the manifest in the asset. The manifest bytes are
returned by `sign` for you to store externally. This is useful when creating
cloud-based or sidecar manifests:

```ruby
builder = C2pa::Builder.from_manifest(manifest)
builder.set_remote_url("https://cdn.example.com/manifest.c2pa")
builder.set_no_embed

manifest_bytes = nil
File.open("input.jpg", "rb") do |src|
  File.open("output.jpg", "wb") do |dst|
    manifest_bytes = builder.sign(signer, "image/jpeg", src, dst)
  end
end

# Store manifest_bytes to your CDN, then read back with:
# C2pa::Reader.open("image/jpeg", File.open("output.jpg", "rb"), manifest_bytes)
```

### Two-phase signing (archive round-trip)

Serialize a builder's state after ingesting ingredients, then restore and sign
later — useful for pipelines where ingest and export happen on different machines:

```ruby
# Phase 1 — ingest
builder = C2pa::Builder.from_manifest(manifest)
File.open("source.jpg", "rb") { |f| builder.add_ingredient({}, "image/jpeg", f) }

archive = StringIO.new("".b)
builder.to_archive(archive)
builder.close

# Phase 2 — sign
archive.rewind
builder = C2pa::Builder.from_archive(archive)
File.open("input.jpg", "rb") do |src|
  File.open("output.jpg", "wb") { |dst| builder.sign(signer, "image/jpeg", src, dst) }
end
builder.close
```

## Supported formats

JPEG, PNG, TIFF, WebP, MP4, MOV, and more. Query at runtime:

```ruby
C2pa::Reader.supported_mime_types  # => ["image/jpeg", "image/png", ...]
C2pa::Builder.supported_mime_types # => ["image/jpeg", "image/png", ...]
```

See the full list in the [c2pa-rs supported formats docs](https://github.com/contentauth/c2pa-rs/blob/main/docs/supported-formats.md).

## Supported signing algorithms

`es256`, `es384`, `es512`, `ps256`, `ps384`, `ps512`, `ed25519`

## Error handling

`Reader.open` raises `C2pa::Error` if the file has no C2PA manifest:

```ruby
begin
  C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) { |r| puts r.json }
rescue C2pa::Error => e
  puts "No manifest: #{e.message}"
end
```

`C2pa::ClosedError` is raised if you call methods on a reader, builder, or
signer after calling `close`.

## Settings

Use `C2pa.load_settings` to configure library behavior:

```ruby
# Disable automatic remote manifest fetching
C2pa.load_settings({ "verify" => { "remote_manifest_fetch" => false } })
```

## Custom library path

To use a custom build of the native library, set `C2PA_LIBRARY_PATH`:

```sh
C2PA_LIBRARY_PATH=/path/to/libc2pa_c.dylib ruby your_script.rb
```

## Get the native library version

```ruby
puts C2pa.version
# => "c2pa-c/0.67.1 c2pa-rs/0.67.1"
```

## Contributing

Contributions are welcome.

### Development setup

```sh
git clone https://github.com/ak-singh/c2pa-ruby.git
cd c2pa-ruby
bin/setup            # bundle install + download native binaries
bundle exec rspec    # run tests
bundle exec rubocop  # run linter
```

Native binaries are not committed to the repo. They are downloaded from
[`contentauth/c2pa-rs` releases](https://github.com/contentauth/c2pa-rs/releases)
into `libs/<platform>/` by `rake update_binaries`. This task runs
automatically before `rake build`, so released gems always include the
binaries.

To target a different `c2pa-rs` version, edit `C2PA_VERSION` in the Rakefile
and re-run `bundle exec rake update_binaries`.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
