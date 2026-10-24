# frozen_string_literal: true

require "json"
require "digest"

module AfFrontier
  module Jsonl
    module_function

    # Yields UTF-8 records from path, optionally verifying the exact bytes against
    # sha256 first. Raises IntegrityError for a hash mismatch or invalid JSONL,
    # and filesystem errors for unreadable paths.
    def read(path, sha256: nil)
      return enum_for(__method__, path, sha256: sha256) unless block_given?

      lines = if sha256
        content = File.binread(path)
        if Digest::SHA256.hexdigest(content) != sha256
          raise IntegrityError, "Artifact hash mismatch: #{path}"
        end
        content.force_encoding("UTF-8").each_line
      else
        File.foreach(path, encoding: "UTF-8")
      end
      lines.with_index(1) do |line, number|
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
