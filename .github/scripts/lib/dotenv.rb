# frozen_string_literal: true

module Dotenv
  KEY_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  module_function

  def merge(files)
    values = {}
    files.each do |file|
      next unless File.exist?(file)

      parse(file).each { |key, value| values[key] = value }
    end
    values
  end

  def parse(file)
    File.readlines(file, chomp: true).each_with_object({}).with_index do |(raw, values), index|
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
end
