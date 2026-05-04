#!/usr/bin/env ruby
# frozen_string_literal: true

# Read a C2PA manifest from a signed image and print its parsed JSON.
#
# Usage: ruby examples/read_manifest.rb [path/to/image.jpg]

require 'c2pa'
require 'json'

path = ARGV[0] || File.expand_path('../spec/fixtures/C.jpg', __dir__)

unless File.exist?(path)
  warn "File not found: #{path}"
  exit 1
end

C2pa::Reader.open('image/jpeg', File.open(path, 'rb')) do |reader|
  data = JSON.parse(reader.json)

  puts "Active manifest: #{data['active_manifest']}"
  puts "Embedded?       #{reader.embedded?}"
  puts "Validation:     #{reader.validation_state}"
  puts
  puts 'Manifests:'
  data['manifests'].each_key { |label| puts "  - #{label}" }
  puts
  puts 'Full manifest JSON:'
  puts JSON.pretty_generate(data)
end
