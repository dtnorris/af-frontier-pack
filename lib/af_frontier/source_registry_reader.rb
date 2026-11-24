# frozen_string_literal: true

module AfFrontier
  class SourceRegistry
    # Adapts the pinned v0.1 resolver's registry hooks for Frontier Pack's eager
    # validation and segment bounds. The owner decides single-file matches.
    class Reader < AFSourceMD::SourceResolver
      # Return a Frontier Pack locator for the trimmed-title request, or nil
      # when neither a mapping nor a filename matches. Refusals use pack errors.
      def resolve(request)
        segments = @segments[request.source_book]
        validate_segment_range(request) if segments
        resolved = super
        # The owner has already required exactly one containing segment. Project
        # its catalog bounds even when several segments reference the same file.
        segment = segments&.find do |entry|
          request.start_page >= entry.fetch(:start_page) && request.end_page <= entry.fetch(:end_page)
        end
        Resolution.new(
          source_id: request.source_book,
          title: request.source_book,
          markdown_path: File.realpath(resolved.path),
          strategy: resolved.strategy,
          warnings: resolved.warnings,
          page_marker_offset: resolved.page_marker_offset,
          segment_start_page: segment&.fetch(:start_page),
          segment_end_page: segment&.fetch(:end_page)
        )
      rescue AFSourceMD::AmbiguousSourceError => error
        raise ResolutionError, error.message
      rescue AFSourceMD::SourceResolutionError => error
        raise ResolutionError, error.message if @mappings.key?(request.source_book)
        nil
      rescue AFSourceMD::ConfigurationError => error
        raise ConfigurationError, error.message
      end

      # Return the two registry file names and their individual owner-resolved
      # locators. Refuse ranges with a containing segment or ambiguous overlaps.
      def reviewed_segments(request)
        title, start_page, end_page = request.to_a
        validate_segment_range(request)
        segments = @segments.fetch(title, []).select do |segment|
          segment.fetch(:start_page) <= end_page && segment.fetch(:end_page) >= start_page
        end.sort_by { |segment| segment.fetch(:start_page) }
        first, second = segments
        unless segments.length == 2 && first.fetch(:end_page) < second.fetch(:start_page)
          raise ResolutionError, "Reviewed source range for #{title.inspect} requires two unambiguous, nonoverlapping registry segments"
        end

        segments.to_h do |segment|
          resolution = resolve(Request.new(title, segment.fetch(:start_page), segment.fetch(:end_page)))
          [segment.fetch(:file), resolution.locator_hash]
        end
      end

      private

      # Load the owner's v0.1 mappings and validate every declared entry's
      # shape. File existence remains a resolution-time check.
      def load_registry(path)
        mappings = super
        @segments = {}
        mappings.each do |title, mapping|
          if segmented_mapping?(mapping)
            @segments[title] = normalize_segmented_mapping(mapping, source_book: title)
          else
            normalize_mapping(mapping, source_book: title)
          end
        end
        mappings
      rescue AFSourceMD::ConfigurationError => error
        raise ConfigurationError, error.message
      end

      # Return the owner's normalized mapping with Frontier Pack's additional
      # blank-filename check. Invalid payloads raise an owner configuration error.
      def normalize_mapping(mapping, source_book:)
        normalized = super
        if normalized.fetch(:file).strip.empty?
          raise AFSourceMD::ConfigurationError,
                "Invalid source mapping for #{source_book.inspect}: structured mapping requires file"
        end
        normalized
      end

      # Refuse ill-formed catalog ranges before checking segment file existence.
      def validate_segment_range(request)
        title, start_page, end_page = request.to_a
        unless start_page.is_a?(Integer) && end_page.is_a?(Integer)
          raise ResolutionError,
                "Segmented source mapping for #{title.inspect} requires integer adventure start_page and end_page"
        end
        if start_page > end_page
          raise ResolutionError, "Invalid adventure page range for #{title.inspect}: #{start_page}–#{end_page}"
        end
      end
    end
    private_constant :Reader
  end
end
