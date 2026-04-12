# frozen_string_literal: true

require 'spec_helper'

RSpec.describe C2pa::Signer do
  let(:cert) { File.read(fixture('es256_certs.pem')) }
  let(:key)  { File.read(fixture('es256_private.key')) }

  describe '.from_info' do
    it 'returns a Signer for valid inputs' do
      s = described_class.from_info(alg: 'es256', cert: cert, key: key)
      expect(s).to be_a(described_class)
      expect(s.closed?).to be(false)
      s.close
    end

    it 'raises C2pa::Error for an invalid algorithm' do
      expect do
        described_class.from_info(alg: 'not-an-alg', cert: cert, key: key)
      end.to raise_error(C2pa::Error, /algorithm/i)
    end

    it 'raises C2pa::Error for an invalid private key' do
      expect do
        described_class.from_info(alg: 'es256', cert: cert, key: 'not-a-key')
      end.to raise_error(C2pa::Error)
    end
  end

  describe '#close' do
    it 'marks the signer as closed' do
      s = described_class.from_info(alg: 'es256', cert: cert, key: key)
      s.close
      expect(s.closed?).to be(true)
    end

    it 'is idempotent' do
      s = described_class.from_info(alg: 'es256', cert: cert, key: key)
      s.close
      expect { s.close }.not_to raise_error
    end
  end

  describe 'GC safety' do
    it 'survives GC stress during from_info' do
      with_gc_stress do
        s = described_class.from_info(alg: 'es256', cert: cert, key: key)
        expect(s).to be_a(described_class)
        s.close
      end
    end
  end
end
