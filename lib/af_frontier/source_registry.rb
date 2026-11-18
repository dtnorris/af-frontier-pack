# frozen_string_literal: true

require "digest"
require "pathname"
require_relative "source_markdown_owner"

module AfFrontier
  # Resolves the catalog's source names into Frontier Pack locators.
  class SourceRegistry
    REGISTRY_SCHEMA_VERSION = "adventurefinder-source-registry/v0.1"

    Resolution = Struct.new(
      :source_id, :title, :markdown_path, :strategy, :warnings,
      :page_marker_offset, :segment_start_page, :segment_end_page,
      keyword_init: true
    ) do
      # Return whether this locator has a Markdown path.
      def resolved?
        !markdown_path.nil?
      end

      # Return the non-null locator fields for downstream consumers.
      def locator_hash
        {
          "path" => markdown_path,
          "strategy" => strategy,
          "warnings" => warnings,
          "page_marker_offset" => page_marker_offset,
          "segment_start_page" => segment_start_page,
          "segment_end_page" => segment_end_page
        }.compact
      end
    end

    Request = Struct.new(:source_book, :start_page, :end_page)
    private_constant :Request

    attr_reader :path, :corpus_root

    # Bind an existing registry and corpus directory, and eagerly validate the
    # mapping shapes. Invalid inputs or owner selection raise ConfigurationError.
    def initialize(path:, corpus_root:)
      @path = Pathname.new(path).expand_path
      @corpus_root = Pathname.new(corpus_root).expand_path
      raise ConfigurationError, "Source registry does not exist: #{@path}" unless @path.file?
      raise ConfigurationError, "Corpus root does not exist: #{@corpus_root}" unless @corpus_root.directory?
      SourceMarkdownOwner.load!
      require_relative "source_registry_reader"
      @reader = Reader.new(source_root: @corpus_root, registry_path: @path)
    end

    # Return the SHA-256 of the registry file. Filesystem errors propagate.
    def sha256
      Digest::SHA256.file(@path).hexdigest
    end

    # Return a locator for a trimmed catalog title and optional page range, or
    # nil when unresolved. Ambiguous or invalid matches raise ResolutionError.
    def resolve(book_title, start_page: nil, end_page: nil)
      title = book_title.to_s.strip
      return nil if title.empty?

      @reader.resolve(Request.new(title, start_page, end_page))
    end
  end
end
