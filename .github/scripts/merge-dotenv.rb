#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/dotenv'
require_relative 'lib/output'

begin
  Dotenv.merge(ARGV).each { |key, value| puts "#{key}=#{value}" }
rescue StandardError => e
  ScriptOutput.fail!(e.message, prefix: 'dotenv merge')
end
