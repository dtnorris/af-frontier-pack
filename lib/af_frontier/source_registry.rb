# frozen_string_literal: true

require "yaml"
require "digest"
require "pathname"

module AfFrontier
  class SourceRegistry
    Entry = Struct.new(:source_id, :title, :markdown_path, :publisher, :page_basis, :page_offset, keyword_init: true) do
      def to_h
        {
          "source_id" => source_id,
          "title" => title,
          "publisher" => publisher,
          "markdown_locator" => { "path" => markdown_path },
          "page_basis" => page_basis,
          "page_offset" => page_offset
        }
      end
    end

    attr_reader :path

    def initialize(path:, corpus_root:)
      @path = Pathname.new(path).expand_path
      @corpus_root = Pathname.new(corpus_root).expand_path
      raise ConfigurationError, "Source registry does not exist: #{@path}" unless @path.file?
      raise ConfigurationError, "Corpus root does not exist: #{@corpus_root}" unless @corpus_root.directory?
      @entries = parse
    end

    def sha256
      Digest::SHA256.file(@path).hexdigest
    end

    def resolve(book_title)
      exact = @entries.select { |entry| entry.title == book_title }
      raise ResolutionError, "Ambiguous source registry match for #{book_title.inspect}" if exact.length > 1
      exact.first
    end

    def entries
      @entries.dup
    end

    private

    def parse
      data = YAML.safe_load(@path.read, permitted_classes: [], aliases: false) || {}
      data = data["sources"] if data.is_a?(Hash) && data["sources"].is_a?(Hash)
      raise ConfigurationError, "Unsupported source registry shape in #{@path}: expected a mapping" unless data.is_a?(Hash)

      data.filter_map do |title, raw|
        normalize_entry(title.to_s, raw)
      end
    rescue Psych::Exception => e
      raise ConfigurationError, "Could not parse source registry #{@path}: #{e.message}"
    end

    def normalize_entry(title, raw)
      attrs = case raw
              when String
                { "path" => raw }
              when Hash
                raw
              else
                return nil
              end

      path = attrs["markdown_path"] || attrs["md_path"] || attrs["path"] || attrs["source_path"] || attrs["source"]
      return nil unless path.is_a?(String) && !path.strip.empty?

      full = Pathname.new(path)
      full = @corpus_root.join(full) unless full.absolute?

      Entry.new(
        source_id: attrs["source_id"] || attrs["id"] || slug(title),
        title: attrs["title"] || title,
        markdown_path: full.expand_path.to_s,
        publisher: attrs["publisher"],
        page_basis: attrs["page_basis"],
        page_offset: Integer(attrs.fetch("page_offset", 0))
      )
    rescue ArgumentError, TypeError
      raise ConfigurationError, "Invalid page_offset for source #{title.inspect} in #{@path}"
    end

    def slug(value)
      value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z/, "")
    end
  end
end
