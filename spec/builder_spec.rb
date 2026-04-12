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

  # Opens source fixture and ensures the file is closed after the block.
  def with_source(&block)
    File.open(source, 'rb', &block)
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

  describe '#add_ingredient' do
    it 'accepts a Hash ingredient definition' do
      b = described_class.new(manifest_json)
      with_source { |f| expect { b.add_ingredient({ 'title' => 'source.jpg' }, 'image/jpeg', f) }.not_to raise_error }
      b.close
    end

    it 'accepts a JSON string ingredient definition' do
      b = described_class.new(manifest_json)
      with_source { |f| expect { b.add_ingredient('{"title":"source.jpg"}', 'image/jpeg', f) }.not_to raise_error }
      b.close
    end

    it 'embeds the ingredient in the signed manifest' do
      b      = described_class.new(manifest_json)
      signer = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key)
      dst    = StringIO.new(''.b)

      with_source { |f| b.add_ingredient({ 'title' => 'source.jpg' }, 'image/jpeg', f) }
      with_source { |f| b.sign(signer, 'image/jpeg', f, dst) }
      signer.close
      b.close

      dst.rewind
      C2pa::Reader.open('image/jpeg', dst) do |r|
        data        = JSON.parse(r.json)
        active      = data['active_manifest']
        ingredients = data['manifests'][active]['ingredients']
        expect(ingredients).not_to be_nil
        expect(ingredients).not_to be_empty
      end
    end

    it 'accumulates multiple ingredients' do
      b      = described_class.new(manifest_json)
      signer = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key)
      dst    = StringIO.new(''.b)

      with_source { |f| b.add_ingredient({ 'title' => 'first.jpg' }, 'image/jpeg', f) }
      with_source { |f| b.add_ingredient({ 'title' => 'second.jpg' }, 'image/jpeg', f) }
      with_source { |f| b.sign(signer, 'image/jpeg', f, dst) }
      signer.close
      b.close

      dst.rewind
      C2pa::Reader.open('image/jpeg', dst) do |r|
        data        = JSON.parse(r.json)
        active      = data['active_manifest']
        ingredients = data['manifests'][active]['ingredients']
        expect(ingredients.length).to be >= 2
      end
    end

    it 'raises C2pa::Error for invalid ingredient JSON' do
      b = described_class.new(manifest_json)
      with_source do |f|
        expect { b.add_ingredient('{ not valid json }', 'image/jpeg', f) }.to raise_error(C2pa::Error)
      end
      b.close
    end

    it 'raises ClosedError after close' do
      b = described_class.new(manifest_json)
      b.close
      with_source do |f|
        expect { b.add_ingredient({}, 'image/jpeg', f) }.to raise_error(C2pa::ClosedError)
      end
    end
  end

  describe '#sign' do
    let(:signer) { C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key) }

    after { signer.close }

    it 'writes a non-empty signed asset to dest_io' do
      b   = described_class.new(manifest_json)
      dst = StringIO.new(''.b)
      with_source { |f| b.sign(signer, 'image/jpeg', f, dst) }
      expect(dst.string.bytesize).to be > 0
      b.close
    end

    it 'returns the raw manifest bytes' do
      b     = described_class.new(manifest_json)
      dst   = StringIO.new(''.b)
      bytes = nil
      with_source { |f| bytes = b.sign(signer, 'image/jpeg', f, dst) }
      expect(bytes).to be_a(String)
      expect(bytes.bytesize).to be > 0
      b.close
    end

    it 'produces a readable manifest — round-trip via Reader' do
      b   = described_class.new(manifest_json)
      dst = StringIO.new(''.b)
      with_source { |f| b.sign(signer, 'image/jpeg', f, dst) }
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
      with_source { |f| b.sign(signer, 'image/jpeg', f, dst) }
      b.close

      dst.rewind
      C2pa::Reader.open('image/jpeg', dst) do |r|
        data          = JSON.parse(r.json)
        active        = data['active_manifest']
        assertions    = data['manifests'][active]['assertions']
        action_assert = assertions.select { |a| a['label'].start_with?('c2pa.actions') }
        actions       = action_assert.flat_map { |a| a.dig('data', 'actions') || [] }
        expect(actions.any? { |a| a['action'] == 'c2pa.published' }).to be(true)
      end
    end

    it 'signs without a timestamp (ta_url: nil)' do
      s   = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key, ta_url: nil)
      b   = described_class.new(manifest_json)
      dst = StringIO.new(''.b)
      with_source { |f| expect { b.sign(s, 'image/jpeg', f, dst) }.not_to raise_error }
      s.close
      b.close
    end

    it 'raises ClosedError after close' do
      b = described_class.new(manifest_json)
      b.close
      with_source do |f|
        expect { b.sign(signer, 'image/jpeg', f, StringIO.new(''.b)) }.to raise_error(C2pa::ClosedError)
      end
    end

    it 'raises ClosedError when signer is closed' do
      s = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key)
      s.close
      b = described_class.new(manifest_json)
      with_source do |f|
        expect { b.sign(s, 'image/jpeg', f, StringIO.new(''.b)) }.to raise_error(C2pa::ClosedError)
      end
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
        with_source { |f| b.sign(signer, 'image/jpeg', f, dst) }
        expect(dst.string.bytesize).to be > 0
        b.close
      end
    end

    it 'survives GC stress during add_ingredient' do
      with_gc_stress do
        b = described_class.new(manifest_json)
        with_source { |f| b.add_ingredient({ 'title' => 'source.jpg' }, 'image/jpeg', f) }
        expect(b.closed?).to be(false)
        b.close
      end
    end
  end
end
