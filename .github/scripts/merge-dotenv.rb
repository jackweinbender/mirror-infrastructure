#!/usr/bin/env ruby
# frozen_string_literal: true

KEY_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
values = {}

begin
  ARGV.each do |file|
    next unless File.exist?(file)

    File.readlines(file, chomp: true).each_with_index do |raw, index|
      line = raw.strip
      next if line.empty? || line.start_with?('#')

      line = line.sub(/\Aexport\s+/, '')
      separator = line.index('=')
      raise "malformed dotenv line #{file}:#{index + 1}" unless separator

      key = line[0...separator].strip
      value = line[(separator + 1)..].strip
      raise "invalid dotenv key #{file}:#{index + 1}" unless KEY_PATTERN.match?(key)

      if value.start_with?('"', "'")
        quote = value[0]
        raise "unterminated dotenv value #{file}:#{index + 1}" unless value.length >= 2 && value.end_with?(quote)
        value = value[1...-1]
      end
      values[key] = value
    end
  end

  values.each { |key, value| puts "#{key}=#{value}" }
rescue StandardError => e
  warn "dotenv merge: #{e.message}"
  exit 1
end
