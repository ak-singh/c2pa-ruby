#!/usr/bin/env ruby
# frozen_string_literal: true

# Sign a JPEG with C2PA provenance metadata using an ES256 cert + key,
# then read the resulting manifest back to verify.
#
# Usage: ruby examples/sign_with_es256.rb

require 'c2pa'
require 'fileutils'

fixtures = File.expand_path('../spec/fixtures', __dir__)
output = File.expand_path('../tmp/signed.jpg', __dir__)

cert = File.read(File.join(fixtures, 'es256_certs.pem'))
key  = File.read(File.join(fixtures, 'es256_private.key'))

manifest = {
  'claim_generator' => 'c2pa-ruby-example/0.1',
  'claim_generator_info' => [{ 'name' => 'c2pa-ruby-example', 'version' => '0.1' }],
  'format' => 'image/jpeg',
  'title' => 'Example Signed Image',
  'assertions' => [
    {
      'label' => 'c2pa.actions',
      'data' => {
        'actions' => [
          { 'action' => 'c2pa.created' }
        ]
      }
    }
  ]
}

FileUtils.mkdir_p(File.dirname(output))

signer = C2pa::Signer.from_info(alg: 'es256', cert: cert, key: key)
builder = C2pa::Builder.from_manifest(manifest)

begin
  File.open(File.join(fixtures, 'earth_apollo17.jpg'), 'rb') do |source|
    File.open(output, 'w+b') do |dest|
      builder.sign(signer, 'image/jpeg', source, dest)
    end
  end
ensure
  signer.close
  builder.close
end

puts "Signed: #{output}"
puts
puts 'Reading back to verify:'
C2pa::Reader.open('image/jpeg', File.open(output, 'rb')) do |reader|
  puts reader.json
end
