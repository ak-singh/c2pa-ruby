# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-12

### Added
- `C2pa::Reader` — read and validate C2PA manifests from any IO object
  - `Reader.open(mime_type, io, manifest_bytes = nil)` with block and non-block forms
  - `#json`, `#detailed_json` — raw manifest store as JSON string
  - `#active_manifest`, `#manifest(label)` — parsed manifest data as Ruby Hash
  - `#validation_state`, `#validation_results` — parsed validation info
  - `#resource_to_stream(uri, dest_io)` — extract embedded resources (thumbnails, etc.)
  - `#embedded?`, `#remote_url` — check manifest location
  - `Reader.supported_mime_types` — query supported formats at runtime
- `C2pa::Builder` — create and sign C2PA manifests
  - `Builder.from_manifest(json_or_hash)`, `Builder.from_archive(io)` — construction
  - `#sign(signer, mime_type, source_io, dest_io)` — sign and embed manifest
  - `#add_action(action)`, `#add_ingredient(json, mime_type, io)`, `#add_resource(uri, io)`
  - `#set_remote_url(url)`, `#set_no_embed` — remote/sidecar manifest support
  - `#to_archive(io)` — serialize builder state for two-phase signing pipelines
  - `Builder.supported_mime_types` — query supported formats at runtime
- `C2pa::Signer` — wrap a certificate and private key for signing
  - `Signer.from_info(alg:, cert:, key:, ta_url: nil)` — supports es256, es384, es512, ps256, ps384, ps512, ed25519
  - `#reserve_size` — query required signature buffer size
- `C2pa.load_settings(json_or_hash)` — configure library behavior (e.g. disable remote manifest fetching)
- `C2pa.version` — native library version string
- `C2PA_LIBRARY_PATH` env var override for custom library paths
- Precompiled native binary for aarch64-apple-darwin (Apple Silicon)
