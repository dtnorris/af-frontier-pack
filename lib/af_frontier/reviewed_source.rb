# frozen_string_literal: true

require "digest"
require "json"

module AfFrontier
  # Binds one operator-reviewed catalog row to the two Markdown files used together.
  class ReviewedSource
    STRATEGY = "reviewed_multi_volume"
    LIMITATION = "The two files are review references. Registry segment bounds do not verify coverage of the catalog span."
    IDENTITY_FIELDS = %w[adventure_id adventure_title source_book start_page end_page].freeze
    SHA256 = /\A[0-9a-f]{64}\z/

    attr_reader :adventure_id

    # Read one private JSON declaration. Missing or malformed input raises ConfigurationError.
    def initialize(path)
      declaration = JSON.parse(File.binread(path), allow_duplicate_key: false)
      unless declaration.is_a?(Hash) && declaration.keys.sort == (IDENTITY_FIELDS + ["files"]).sort
        raise ConfigurationError, "Reviewed source declaration requires #{(IDENTITY_FIELDS + ['files']).join(', ')}"
      end

      @identity = declaration.slice(*IDENTITY_FIELDS)
      @adventure_id, title, book, start_page, end_page = @identity.values_at(*IDENTITY_FIELDS)
      @files = declaration.fetch("files")
      unless [adventure_id, title, book].all? { |value| value.is_a?(String) && !value.strip.empty? } &&
             start_page.is_a?(Integer) && end_page.is_a?(Integer) && start_page.positive? && start_page <= end_page &&
             @files.is_a?(Hash) && @files.length == 2 &&
             @files.all? { |file, sha| !file.strip.empty? && sha.is_a?(String) && SHA256.match?(sha) }
        raise ConfigurationError, "Reviewed source declaration requires a catalog identity, ordered integer pages, and two files with SHA-256 digests"
      end
    rescue JSON::ParserError, SystemCallError => error
      raise ConfigurationError, "Cannot read reviewed source declaration: #{error.message}"
    end

    # Return a metadata-only locator for the matching row. Stale identity, file
    # names, bytes or incompatible registry mappings raise ResolutionError.
    def locator_for(row, registry:)
      start_page = row["Start Page"]
      end_page = row["End Page"]
      book = row["Source Book"].to_s.strip
      identity = {
        "adventure_id" => row.fetch("ADV - ID").to_s.strip,
        "adventure_title" => row["Adventure Title"].to_s.strip,
        "source_book" => book,
        "start_page" => start_page,
        "end_page" => end_page
      }
      unless @identity.eql?(identity)
        raise ResolutionError, "Reviewed source declaration does not match catalog identity for #{adventure_id}"
      end

      segments = registry.reviewed_segments(book, start_page:, end_page:)
      paths = segments.values.map { |segment| segment.fetch("path") }
      unless @files.keys.sort == segments.keys.sort && !File.identical?(*paths)
        raise ResolutionError, "Reviewed source files do not match two distinct registry files for #{adventure_id}"
      end

      references = segments.map do |file, locator|
        sha = @files.fetch(file)
        unless Digest::SHA256.file(locator.fetch("path")).hexdigest == sha
          raise ResolutionError, "Reviewed source hash mismatch for #{adventure_id}: #{file}"
        end
        locator.merge("content_sha256" => sha)
      end

      {
        "source_id" => book,
        "start_page" => start_page,
        "end_page" => end_page,
        "strategy" => STRATEGY,
        "exact_excerpt" => false,
        "warnings" => [LIMITATION],
        "source_references" => references
      }
    rescue SystemCallError => error
      raise ResolutionError, "Cannot verify reviewed source for #{adventure_id}: #{error.message}"
    end
  end
end
