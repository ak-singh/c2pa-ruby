# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'

RSpec.describe C2pa::Reader do
  # C.jpg  — JPEG with a single embedded C2PA manifest
  # earth_apollo17.jpg — JPEG with no C2PA manifest (ManifestNotFound)
  let(:signed_jpeg)    { fixture('C.jpg') }
  let(:unsigned_jpeg)  { fixture('earth_apollo17.jpg') }

  describe '.supported_mime_types' do
    it 'returns a non-empty array of strings' do
      types = described_class.supported_mime_types
      expect(types).to be_an(Array)
      expect(types).not_to be_empty
      expect(types).to all(be_a(String))
    end

    it 'includes image/jpeg' do
      expect(described_class.supported_mime_types).to include('image/jpeg')
    end
  end

  describe '.open with manifest_bytes' do
    let(:cert) { File.read(fixture('es256_certs.pem')) }
    let(:key)  { File.read(fixture('es256_private.key')) }
    let(:source) { fixture('C.jpg') }

    def sign_no_embed
      signer  = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key)
      builder = C2pa::Builder.from_manifest(
        'claim_generator' => 'c2pa-ruby-test/0.1.0', 'assertions' => []
      )
      builder.set_remote_url('https://cdn.example.com/manifest.c2pa')
      builder.set_no_embed
      dst   = StringIO.new(''.b)
      bytes = File.open(source, 'rb') { |f| builder.sign(signer, 'image/jpeg', f, dst) }
      [dst, bytes]
    ensure
      signer&.close
      builder&.close
    end

    it 'reads manifest from externally-supplied bytes (set_no_embed round-trip)' do
      dst, bytes = sign_no_embed
      dst.rewind
      described_class.open('image/jpeg', dst, bytes) do |r|
        data = JSON.parse(r.json)
        expect(data).to have_key('manifests')
      end
    end

    it 'raises C2pa::Error when asset has no embedded manifest and no bytes given' do
      dst, = sign_no_embed
      dst.rewind
      expect do
        described_class.open('image/jpeg', dst)
      end.to raise_error(C2pa::Error)
    end

    it 'raises TypeError for non-String manifest_bytes' do
      File.open(source, 'rb') do |f|
        expect do
          described_class.open('image/jpeg', f, 12_345)
        end.to raise_error(TypeError, /manifest_bytes/)
      end
    end

    it 'raises C2pa::Error for empty manifest_bytes' do
      File.open(source, 'rb') do |f|
        expect do
          described_class.open('image/jpeg', f, '')
        end.to raise_error(C2pa::Error)
      end
    end
  end

  describe '.open without a block' do
    it 'returns a Reader instance' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      expect(reader).to be_a(described_class)
      reader.close
    end

    it 'reader is not closed before close is called' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      expect(reader.closed?).to be(false)
      reader.close
    end
  end

  describe '.open with a block' do
    it 'yields a Reader and closes it on exit' do
      reader_ref = nil
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        reader_ref = r
        expect(r).to be_a(described_class)
        expect(r.closed?).to be(false)
      end
      expect(reader_ref.closed?).to be(true)
    end

    it 'closes the reader even when the block raises' do
      reader_ref = nil
      expect do
        described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
          reader_ref = r
          raise 'boom'
        end
      end.to raise_error(RuntimeError, 'boom')
      expect(reader_ref.closed?).to be(true)
    end
  end

  describe '#json' do
    it 'returns a non-empty JSON string' do
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        expect(r.json).to be_a(String)
        expect(r.json).not_to be_empty
      end
    end

    it 'parses into a hash with a manifests key' do
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        data = JSON.parse(r.json)
        expect(data).to have_key('manifests')
      end
    end

    it 'raises ClosedError after close' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      reader.close
      expect { reader.json }.to raise_error(C2pa::ClosedError)
    end
  end

  describe '#detailed_json' do
    it 'returns a non-empty JSON string' do
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        expect(r.detailed_json).to be_a(String)
        expect(r.detailed_json).not_to be_empty
      end
    end

    it 'parses into a hash with a manifests key' do
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        data = JSON.parse(r.detailed_json)
        expect(data).to have_key('manifests')
      end
    end

    it 'raises ClosedError after close' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      reader.close
      expect { reader.detailed_json }.to raise_error(C2pa::ClosedError)
    end
  end

  describe '#embedded?' do
    it 'returns true for a file with an embedded manifest' do
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        expect(r.embedded?).to be(true)
      end
    end

    it 'raises ClosedError after close' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      reader.close
      expect { reader.embedded? }.to raise_error(C2pa::ClosedError)
    end
  end

  describe '#remote_url' do
    it 'returns nil for a file with an embedded (not remote) manifest' do
      described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
        expect(r.remote_url).to be_nil
      end
    end

    it 'raises ClosedError after close' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      reader.close
      expect { reader.remote_url }.to raise_error(C2pa::ClosedError)
    end

    it 'returns a String when the manifest is remote' do
      # cloud.jpg has a remote manifest hosted on Adobe's CDN. The SDK fetches it
      # automatically; remote_url returns the URL after a successful fetch.
      described_class.open('image/jpeg', File.open(fixture('cloud.jpg'), 'rb')) do |r|
        url = r.remote_url
        expect(url).to be_a(String)
        expect(url).not_to be_empty
        expect(r.embedded?).to be(false)
      end
    end
  end

  describe '#close' do
    it 'marks the reader as closed' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      reader.close
      expect(reader.closed?).to be(true)
    end

    it 'is idempotent — can be called multiple times without error' do
      reader = described_class.open('image/jpeg', File.open(signed_jpeg, 'rb'))
      reader.close
      expect { reader.close }.not_to raise_error
    end
  end

  describe 'error handling' do
    it 'raises C2pa::Error for a file with no C2PA manifest' do
      expect do
        described_class.open('image/jpeg', File.open(unsigned_jpeg, 'rb'))
      end.to raise_error(C2pa::Error, /ManifestNotFound/)
    end

    it 'reads from a StringIO (in-memory stream)' do
      bytes = File.binread(signed_jpeg)
      io = StringIO.new(bytes)
      described_class.open('image/jpeg', io) do |r|
        expect(r.json).not_to be_empty
      end
    end
  end

  describe 'GC safety' do
    it 'survives GC stress during open+read' do
      with_gc_stress do
        described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
          expect(r.json).not_to be_empty
        end
      end
    end

    it 'survives GC stress with all reader methods' do
      with_gc_stress do
        described_class.open('image/jpeg', File.open(signed_jpeg, 'rb')) do |r|
          expect(r.json).not_to be_empty
          expect(r.detailed_json).not_to be_empty
          expect(r.embedded?).to be(true).or be(false)
          r.remote_url # return value not asserted; verifying no crash
        end
      end
    end
  end
end
