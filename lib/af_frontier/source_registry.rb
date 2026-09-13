# frozen_string_literal: true

require "yaml"
require "digest"
require "pathname"

module AfFrontier
  class SourceRegistry
    REGISTRY_SCHEMA_VERSION = "adventurefinder-source-registry/v0.1"

    Resolution = Struct.new(
      :source_id, :title, :markdown_path, :strategy, :warnings,
      :page_marker_offset, :segment_start_page, :segment_end_page,
      keyword_init: true
    ) do
      def resolved?
        !markdown_path.nil?
      end

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

    attr_reader :path, :corpus_root

    def initialize(path:, corpus_root:)
      @path = Pathname.new(path).expand_path
      @corpus_root = Pathname.new(corpus_root).expand_path
      raise ConfigurationError, "Source registry does not exist: #{@path}" unless @path.file?
      raise ConfigurationError, "Corpus root does not exist: #{@corpus_root}" unless @corpus_root.directory?
      @mappings = parse
    end

    def sha256
      Digest::SHA256.file(@path).hexdigest
    end

    def resolve(book_title, start_page: nil, end_page: nil)
      title = book_title.to_s.strip
      return nil if title.empty?

      explicit = @mappings[title]
      return resolve_explicit(title, explicit, start_page, end_page) if explicit

      candidates = markdown_files.select do |candidate|
        source_key = normalize_source(title)
        file_key = normalize_filename(File.basename(candidate, File.extname(candidate)))
        file_key == source_key || file_key.include?(source_key) || source_key.include?(file_key)
      end

      case candidates.length
      when 1
        Resolution.new(
          source_id: title,
          title: title,
          markdown_path: File.realpath(candidates.first),
          strategy: "normalized_filename",
          warnings: ["SOURCE_RESOLVED_BY_FILENAME"],
          page_marker_offset: 0
        )
      when 0
        nil
      else
        raise ResolutionError,
              "Multiple Markdown sources match #{title.inspect}: #{candidates.join(', ')}"
      end
    end

    private

    def parse
      raw = YAML.safe_load_file(@path, aliases: true) || {}
      unless raw.is_a?(Hash)
        raise ConfigurationError, "Invalid source registry #{@path}: expected top-level mapping"
      end

      unknown = raw.keys.map(&:to_s) - %w[schema_version sources]
      unless unknown.empty?
        raise ConfigurationError,
              "Invalid source registry #{@path}: unknown top-level fields #{unknown.join(', ')}"
      end

      version = raw["schema_version"] || raw[:schema_version]
      unless version == REGISTRY_SCHEMA_VERSION
        raise ConfigurationError,
              "Unsupported source registry schema #{version.inspect}; expected #{REGISTRY_SCHEMA_VERSION.inspect}"
      end

      sources = raw["sources"] || raw[:sources]
      unless sources.is_a?(Hash)
        raise ConfigurationError, "Invalid source registry #{@path}: sources must be a mapping"
      end

      sources.each_with_object({}) do |(source_book, mapping), normalized|
        unless source_book.is_a?(String) && !source_book.strip.empty?
          raise ConfigurationError,
                "Invalid source registry #{@path}: source-book keys must be nonblank strings"
        end
        normalized[source_book] = normalize_mapping(source_book, mapping)
      end
    rescue Psych::Exception => e
      raise ConfigurationError, "Invalid source registry YAML #{@path}: #{e.message}"
    end

    def normalize_mapping(source_book, mapping)
      unless mapping.is_a?(Hash)
        raise ConfigurationError,
              "Invalid source mapping for #{source_book.inspect}: expected mapping with file or segments"
      end

      if mapping.key?("segments") || mapping.key?(:segments)
        normalize_segmented_mapping(source_book, mapping)
      else
        unknown = mapping.keys.map(&:to_s) - %w[file page_marker_offset]
        unless unknown.empty?
          raise ConfigurationError,
                "Invalid source mapping for #{source_book.inspect}: unknown fields #{unknown.join(', ')}"
        end

        file = mapping["file"] || mapping[:file]
        unless file.is_a?(String) && !file.strip.empty?
          raise ConfigurationError,
                "Invalid source mapping for #{source_book.inspect}: structured mapping requires file"
        end

        {
          type: :file,
          file: file,
          page_marker_offset: normalize_page_marker_offset(
            mapping["page_marker_offset"] || mapping[:page_marker_offset] || "+0",
            source_book: source_book
          )
        }
      end
    end

    def normalize_segmented_mapping(source_book, mapping)
      incompatible = mapping.keys.map(&:to_s) - ["segments"]
      unless incompatible.empty?
        raise ConfigurationError,
              "Invalid source mapping for #{source_book.inspect}: segments cannot be combined with #{incompatible.join(', ')}"
      end

      raw_segments = mapping["segments"] || mapping[:segments]
      unless raw_segments.is_a?(Array) && !raw_segments.empty?
        raise ConfigurationError,
              "Invalid source mapping for #{source_book.inspect}: segments must be a non-empty list"
      end

      segments = raw_segments.each_with_index.map do |segment, index|
        unless segment.is_a?(Hash)
          raise ConfigurationError,
                "Invalid source segment #{index + 1} for #{source_book.inspect}: expected mapping"
        end
        unknown = segment.keys.map(&:to_s) - %w[start_page end_page file page_marker_offset]
        unless unknown.empty?
          raise ConfigurationError,
                "Invalid source segment #{index + 1} for #{source_book.inspect}: unknown fields #{unknown.join(', ')}"
        end

        start_page = segment["start_page"] || segment[:start_page]
        end_page = segment["end_page"] || segment[:end_page]
        unless start_page.is_a?(Integer) && end_page.is_a?(Integer) && start_page.positive? && end_page.positive?
          raise ConfigurationError,
                "Invalid source segment #{index + 1} for #{source_book.inspect}: start_page and end_page must be positive integers"
        end
        if start_page > end_page
          raise ConfigurationError,
                "Invalid source segment #{index + 1} for #{source_book.inspect}: start_page exceeds end_page"
        end

        file = segment["file"] || segment[:file]
        unless file.is_a?(String) && !file.strip.empty?
          raise ConfigurationError,
                "Invalid source segment #{index + 1} for #{source_book.inspect}: file is required"
        end

        {
          start_page: start_page,
          end_page: end_page,
          file: file,
          page_marker_offset: normalize_page_marker_offset(
            segment["page_marker_offset"] || segment[:page_marker_offset] || "+0",
            source_book: source_book
          )
        }
      end

      { type: :segments, segments: segments }
    end

    def resolve_explicit(title, mapping, start_page, end_page)
      selected = if mapping.fetch(:type) == :segments
        select_segment(title, mapping.fetch(:segments), start_page, end_page)
      else
        mapping
      end

      full_path = absolute_or_rooted(selected.fetch(:file))
      unless File.file?(full_path)
        raise ResolutionError,
              "Configured source mapping for #{title.inspect} does not exist: #{full_path}"
      end

      Resolution.new(
        source_id: title,
        title: title,
        markdown_path: File.realpath(full_path),
        strategy: mapping.fetch(:type) == :segments ? "explicit_segment_mapping" : "explicit_mapping",
        warnings: [],
        page_marker_offset: selected.fetch(:page_marker_offset),
        segment_start_page: selected[:start_page],
        segment_end_page: selected[:end_page]
      )
    end

    def select_segment(title, segments, start_page, end_page)
      unless start_page.is_a?(Integer) && end_page.is_a?(Integer)
        raise ResolutionError,
              "Segmented source mapping for #{title.inspect} requires integer adventure start_page and end_page"
      end
      raise ResolutionError, "Invalid adventure page range for #{title.inspect}: #{start_page}–#{end_page}" if start_page > end_page

      segments.each do |segment|
        path = absolute_or_rooted(segment.fetch(:file))
        unless File.file?(path)
          raise ResolutionError,
                "Configured source segment for #{title.inspect} does not exist: #{path}"
        end
      end

      matches = segments.select do |segment|
        start_page >= segment.fetch(:start_page) && end_page <= segment.fetch(:end_page)
      end
      if matches.empty?
        raise ResolutionError,
              "No configured source segment for #{title.inspect} contains adventure range #{start_page}–#{end_page}"
      end
      if matches.length > 1
        raise ResolutionError,
              "Multiple configured source segments for #{title.inspect} contain adventure range #{start_page}–#{end_page}"
      end
      matches.first
    end

    def normalize_page_marker_offset(raw_offset, source_book:)
      text = raw_offset.to_s
      unless text.match?(/\A[+-]\d+\z/)
        raise ConfigurationError,
              "Invalid page_marker_offset for #{source_book.inspect}: use an explicitly signed value such as \"+3\" or \"-3\""
      end
      Integer(text, 10)
    end

    def absolute_or_rooted(value)
      path = Pathname.new(value)
      path.absolute? ? path.expand_path.to_s : @corpus_root.join(path).expand_path.to_s
    end

    def markdown_files
      @markdown_files ||= Dir.glob(@corpus_root.join("**", "*.md").to_s).sort
    end

    def normalize_source(value)
      ascii = value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "")
      ascii.downcase.gsub("&", "and").gsub(/[^a-z0-9]+/, "")
    end

    def normalize_filename(value)
      cleaned = value.to_s
        .sub(/_LLM_Edition.*\z/i, "")
        .sub(/[-_ ]LLM[-_ ]Edition.*\z/i, "")
        .sub(/\(\d+\)\z/, "")
      normalize_source(cleaned.tr("_", " "))
    end
  end
end
