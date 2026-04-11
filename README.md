# c2pa-ruby

Ruby bindings for the [C2PA](https://c2pa.org) reference SDK (`c2pa-rs`).

[C2PA](https://c2pa.org) (Coalition for Content Provenance and Authenticity) is an open standard for attaching cryptographically signed provenance metadata to digital media. This gem provides Ruby bindings that can:

- Read and validate C2PA manifest data from media files in supported formats
- Create and sign manifest data, and attach it to media files in supported formats *(coming soon)*

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

## Usage

### Read a manifest

```ruby
require "c2pa"
require "json"

C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  data = JSON.parse(reader.json)
  puts data["manifests"].keys
end
```

The block form is recommended — the reader and all native resources are released automatically when the block exits, even if an exception is raised.

You can also manage the lifecycle manually:

```ruby
reader = C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb"))
puts reader.json
reader.close
```

### Check if a manifest is embedded or remote

```ruby
C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  if reader.embedded?
    puts reader.json
  else
    puts "Remote manifest at: #{reader.remote_url}"
  end
end
```

For assets with remote manifests, the library fetches the manifest over the network
automatically during `Reader.open`. If the network is unavailable, `Reader.open` raises
`C2pa::Error`.

### Read from any IO object

The reader works with any seekable IO — a file, a `StringIO`, a cloud storage stream, etc.:

```ruby
bytes = download_from_s3("photo.jpg")
io    = StringIO.new(bytes)

C2pa::Reader.open("image/jpeg", io) do |reader|
  puts reader.json
end
```

### Get the native library version

```ruby
puts C2pa.version
# => "c2pa-c/0.67.1 c2pa-rs/0.67.1"
```

## Supported formats

The underlying `c2pa-rs` library supports a wide range of media formats including JPEG, PNG, TIFF, MP4, MOV, WebP, and more. See the [supported formats list](https://github.com/contentauth/c2pa-rs/blob/main/docs/supported-formats.md) for the full reference.

## Handling files without a manifest

If the file has no C2PA manifest, `Reader.open` raises `C2pa::Error`. Handle it explicitly if you are processing a mix of signed and unsigned assets:

```ruby
begin
  C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
    puts reader.json
  end
rescue C2pa::Error => e
  puts "No manifest: #{e.message}"
end
```

## Custom library path

To use a custom build of the native library, set the `C2PA_LIBRARY_PATH` environment variable:

```sh
C2PA_LIBRARY_PATH=/path/to/libc2pa_c.dylib ruby your_script.rb
```

## Contributing

Contributions are welcome. To run the test suite locally:

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
