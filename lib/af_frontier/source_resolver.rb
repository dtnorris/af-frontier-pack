# frozen_string_literal: true

require_relative "source_markdown_owner"

module AfFrontier
  # Reads retained pack locators and renders their canonical Markdown for display.
  class SourceResolver
    # Bind a pack reader. The default pack opens the configured output directory.
    def initialize(pack: Pack.new)
      @pack = pack
    end

    # Return the stored locator for the adventure. Pack lookup errors propagate.
    def locator(adventure_id)
      @pack.fetch(adventure_id).fetch("source_locator")
    end

    # Return the strict page slice rendered with one final newline. Missing
    # owner selection or unreadable boundaries raise the corresponding pack error.
    def emit(adventure_id)
      owner = SourceMarkdownOwner.load!
      locator = locator(adventure_id)
      path = locator["path"]
      offset = Integer(locator.fetch("page_marker_offset", 0))
      start_page = integer_or_nil(locator["start_page"])
      end_page = integer_or_nil(locator["end_page"])

      raise ResolutionError, "No canonical Markdown source resolved for #{adventure_id}" unless path && File.file?(path)
      raise ResolutionError, "Cannot emit source for #{adventure_id}: missing start/end page" unless start_page && end_page
      raise ResolutionError, "Cannot emit source for #{adventure_id}: start page exceeds end page" if start_page > end_page

      raw_text(owner, path, start_page:, end_page:, offset:).rstrip + "\n"
    end

    private

    # Return the owner's raw UTF-8 slice for the locator's canonical range.
    # Boundary or source refusals become Frontier Pack resolution errors.
    def raw_text(owner, path, start_page:, end_page:, offset:)
      owner::SourceDocument.new(path).extract(start_page:, end_page:, page_marker_offset: offset).text
    rescue AFSourceMD::SourceBoundaryError, AFSourceMD::SourceResolutionError => error
      raise ResolutionError, error.message
    end

    # Coerce a retained catalog page value to Integer, or nil if unusable.
    def integer_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
