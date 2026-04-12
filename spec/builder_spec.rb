# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'

RSpec.describe C2pa::Builder do
  let(:cert)   { File.read(fixture('es256_certs.pem')) }
  let(:key)    { File.read(fixture('es256_private.key')) }
  let(:source) { fixture('C.jpg') }

  let(:manifest_json) do
    { 'claim_generator' => 'c2pa-ruby-test/0.1.0', 'assertions' => [] }
  end

  describe '.new' do
    it 'accepts a JSON string' do
      b = described_class.new(JSON.generate(manifest_json))
      expect(b).to be_a(described_class)
      b.close
    end

    it 'accepts a Hash' do
      b = described_class.new(manifest_json)
      expect(b).to be_a(described_class)
      b.close
    end

    it 'is not closed after creation' do
      b = described_class.new(manifest_json)
      expect(b.closed?).to be(false)
      b.close
    end

    it 'raises C2pa::Error for invalid JSON' do
      expect do
        described_class.new('{ not valid json }')
      end.to raise_error(C2pa::Error)
    end
  end

  describe '#add_action' do
    it 'accepts a bare action label string' do
      b = described_class.new(manifest_json)
      expect { b.add_action('c2pa.published') }.not_to raise_error
      b.close
    end

    it 'accepts a Hash action definition' do
      b = described_class.new(manifest_json)
      expect { b.add_action({ 'action' => 'c2pa.edited' }) }.not_to raise_error
      b.close
    end

    it 'accepts a pre-serialized JSON string' do
      b = described_class.new(manifest_json)
      expect { b.add_action('{"action":"c2pa.published"}') }.not_to raise_error
      b.close
    end

    it 'raises ClosedError after close' do
      b = described_class.new(manifest_json)
      b.close
      expect { b.add_action('c2pa.published') }.to raise_error(C2pa::ClosedError)
    end
  end

  describe '#sign' do
    let(:signer) { C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key) }

    after { signer.close }

    it 'writes a non-empty signed asset to dest_io' do
      b   = described_class.new(manifest_json)
      dst = StringIO.new(''.b)
      b.sign(signer, 'image/jpeg', File.open(source, 'rb'), dst)
      expect(dst.string.bytesize).to be > 0
      b.close
    end

    it 'returns the raw manifest bytes' do
      b     = described_class.new(manifest_json)
      dst   = StringIO.new(''.b)
      bytes = b.sign(signer, 'image/jpeg', File.open(source, 'rb'), dst)
      expect(bytes).to be_a(String)
      expect(bytes.bytesize).to be > 0
      b.close
    end

    it 'produces a readable manifest — round-trip via Reader' do
      b   = described_class.new(manifest_json)
      dst = StringIO.new(''.b)
      b.sign(signer, 'image/jpeg', File.open(source, 'rb'), dst)
      b.close

      dst.rewind
      C2pa::Reader.open('image/jpeg', dst) do |r|
        data = JSON.parse(r.json)
        expect(data).to have_key('manifests')
      end
    end

    it 'embeds the action in the signed manifest' do
      b = described_class.new(manifest_json)
      b.add_action('c2pa.published')
      dst = StringIO.new(''.b)
      b.sign(signer, 'image/jpeg', File.open(source, 'rb'), dst)
      b.close

      dst.rewind
      C2pa::Reader.open('image/jpeg', dst) do |r|
        data          = JSON.parse(r.json)
        assertions    = data['manifests'].values.first['assertions']
        action_assert = assertions.select { |a| a['label'].start_with?('c2pa.actions') }
        actions       = action_assert.flat_map { |a| a.dig('data', 'actions') || [] }
        expect(actions.any? { |a| a['action'] == 'c2pa.published' }).to be(true)
      end
    end

    it 'signs without a timestamp (ta_url: nil)' do
      s   = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key, ta_url: nil)
      b   = described_class.new(manifest_json)
      dst = StringIO.new(''.b)
      expect { b.sign(s, 'image/jpeg', File.open(source, 'rb'), dst) }.not_to raise_error
      s.close
      b.close
    end

    it 'raises ClosedError after close' do
      b = described_class.new(manifest_json)
      b.close
      expect do
        b.sign(signer, 'image/jpeg', File.open(source, 'rb'), StringIO.new(''.b))
      end.to raise_error(C2pa::ClosedError)
    end

    it 'raises ClosedError when signer is closed' do
      s = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key)
      s.close
      b = described_class.new(manifest_json)
      expect do
        b.sign(s, 'image/jpeg', File.open(source, 'rb'), StringIO.new(''.b))
      end.to raise_error(C2pa::ClosedError)
      b.close
    end
  end

  describe '#close' do
    it 'marks the builder as closed' do
      b = described_class.new(manifest_json)
      b.close
      expect(b.closed?).to be(true)
    end

    it 'is idempotent' do
      b = described_class.new(manifest_json)
      b.close
      expect { b.close }.not_to raise_error
    end
  end

  describe 'GC safety' do
    let(:signer) { C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key) }

    after { signer.close }

    it 'survives GC stress during sign' do
      with_gc_stress do
        b   = described_class.new(manifest_json)
        dst = StringIO.new(''.b)
        b.sign(signer, 'image/jpeg', File.open(source, 'rb'), dst)
        expect(dst.string.bytesize).to be > 0
        b.close
      end
    end
  end
end
