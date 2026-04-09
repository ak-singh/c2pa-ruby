# c2pa-ruby

Ruby bindings for the [C2PA](https://c2pa.org) reference SDK (`c2pa-rs`).

C2PA (Coalition for Content Provenance and Authenticity) defines a standard for attaching cryptographically signed provenance metadata to digital media. This gem provides the first official Ruby bindings, including full support for the **proxy-based deferred signing workflow** used in cloud media pipelines.

Ships with precompiled native binaries — **no Rust toolchain required**.

## Status

| Milestone | Status |
|---|---|
| M1 — Library loading + version | ✅ Done |
| M2 — Read manifests | 🔄 In progress |
| M3 — Build and sign | Planned |
| M4 — Proxy / deferred signing | Planned |

## Installation

Add to your Gemfile:

```ruby
gem "c2pa"
```

Or install directly:

```sh
gem install c2pa
```

**Supported platforms:**
- macOS Apple Silicon (`aarch64-apple-darwin`)
- macOS Intel (`x86_64-apple-darwin`)
- Linux x86_64 (`x86_64-unknown-linux-gnu`)

## Usage

### Check the native library version

```ruby
require "c2pa"
puts C2pa.version
# => "c2pa-c/0.28.0 c2pa-rs/0.79.0"
```

### Read a manifest (Milestone 2 — coming soon)

```ruby
C2pa::Reader.open("image/jpeg", File.open("photo.jpg", "rb")) do |reader|
  puts reader.json          # manifest as JSON string
  puts reader.embedded?     # true if manifest is embedded
end
```

### Sign a file (Milestone 3 — coming soon)

```ruby
signer = C2pa::Signer.from_pem(
  cert: File.read("cert.pem"),
  key:  File.read("key.pem"),
  alg:  "es256"
)

C2pa::Builder.new(manifest_json).sign(
  signer:   signer,
  format:   "image/jpeg",
  input:    File.open("input.jpg",  "rb"),
  output:   File.open("output.jpg", "wb")
)
```

### Proxy / deferred signing workflow (Milestone 4 — coming soon)

```ruby
# Phase 1 — Ingest (original present, run once at upload time)
builder = C2pa::Builder.new(ingredient_manifest_json)
builder.add_ingredient(ingredient_def, "image/jpeg", original_stream)
archive_bytes = builder.to_archive     # store in your provenance database

# Phase 4 — Export (original absent, run at delivery time)
C2pa::Builder.from_archive(StringIO.new(archive_bytes))
             .sign(signer, "image/jpeg", proxy_stream, output_stream)
```

## Custom library path

If you need to use a custom build of the native library:

```sh
C2PA_LIBRARY_PATH=/path/to/libc2pa_c.dylib ruby your_script.rb
```

## Development

```sh
bundle install
bundle exec rspec          # run tests
bundle exec rubocop        # lint
bundle exec rake version   # print native library version
```

## License

Licensed under either of Apache License 2.0 or MIT License at your option.
See [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE).
