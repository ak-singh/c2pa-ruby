# frozen_string_literal: true

require 'spec_helper'

RSpec.describe C2pa do
  describe '.version' do
    subject(:ver) { described_class.version }

    it 'returns a non-empty string' do
      expect(ver).to be_a(String)
      expect(ver).not_to be_empty
    end

    it 'contains a c2pa-c version component' do
      expect(ver).to match(%r{c2pa-c(-ffi)?/\d+\.\d+\.\d+})
    end

    it 'contains a c2pa-rs version component' do
      expect(ver).to match(%r{c2pa-rs/\d+\.\d+\.\d+})
    end

    it 'is idempotent — returns the same string on repeated calls' do
      first  = described_class.version
      second = described_class.version
      expect(first).to eq(second)
    end
  end

  describe 'VERSION constant' do
    it 'follows semantic versioning' do
      expect(C2pa::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe C2pa::Loader do
    describe '.library_path' do
      it 'returns an existing file path' do
        expect(File.exist?(described_class.library_path)).to be(true)
      end

      it 'points to a dynamic library' do
        expect(described_class.library_path).to match(/\.(dylib|so)$/)
      end

      context 'when C2PA_LIBRARY_PATH points to a missing file' do
        around do |example|
          original = ENV.fetch('C2PA_LIBRARY_PATH', nil)
          ENV['C2PA_LIBRARY_PATH'] = '/nonexistent/libc2pa_c.dylib'
          example.run
          ENV['C2PA_LIBRARY_PATH'] = original
        end

        it 'raises LibraryNotFoundError' do
          expect { described_class.library_path }.to raise_error(C2pa::LibraryNotFoundError, /C2PA_LIBRARY_PATH/)
        end
      end
    end
  end

  describe C2pa::API do
    it 'loads without error' do
      expect { described_class }.not_to raise_error
    end

    describe 'REQUIRED_FUNCTIONS' do
      it 'are all callable on the module' do
        described_class::REQUIRED_FUNCTIONS.each do |fn|
          expect(described_class).to respond_to(fn),
                                     "expected C2pa::API to respond to #{fn}"
        end
      end
    end

    describe '.last_error' do
      it 'returns a String when an error is present' do
        # Trigger a known error by attempting to read a file with no manifest.
        begin
          C2pa::Reader.open('image/jpeg',
                            File.open(File.join(__dir__, 'fixtures', 'earth_apollo17.jpg'), 'rb'))
        rescue C2pa::Error
          # expected — the library now has an error in its thread-local slot
        end
        expect(described_class.last_error).to be_a(String)
      end
    end
  end
end
