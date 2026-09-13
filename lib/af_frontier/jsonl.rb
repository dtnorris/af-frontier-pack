# frozen_string_literal: true

require "json"

module AfFrontier
  module Jsonl
    module_function

    def read(path)
      return enum_for(__method__, path) unless block_given?

      File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
        next if line.strip.empty?
        yield JSON.parse(line)
      rescue JSON::ParserError => e
        raise IntegrityError, "Invalid JSONL at #{path}:#{number}: #{e.message}"
      end
    end

    def write(path, records)
      File.open(path, "w", encoding: "UTF-8") do |io|
        records.each { |record| io.puts(JSON.generate(record)) }
      end
    end
  end
end
