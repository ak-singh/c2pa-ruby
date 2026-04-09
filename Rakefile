# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[rubocop spec]

desc 'Run specs only (skip linting)'
task test: :spec

desc 'Print the native library version'
task :version do
  require 'c2pa'
  puts C2pa.version
end
