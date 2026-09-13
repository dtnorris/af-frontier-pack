# frozen_string_literal: true

module AfFrontier
  class SourceResolver
    def initialize(pack: Pack.new, source_registry: nil)
      @pack = pack
      @source_registry = source_registry
    end

    def locator(adventure_id)
      record = @pack.fetch(adventure_id)
      record.fetch("source_locator")
    end

    def emit(adventure_id)
      locator = locator(adventure_id)
      path = locator["path"]
      basis = locator["page_basis"]
      offset = Integer(locator.fetch("page_offset", 0))
      start_page = integer_or_nil(locator["start_page"])
      end_page = integer_or_nil(locator["end_page"])

      raise ResolutionError, "No canonical Markdown source resolved for #{adventure_id}" unless path && File.file?(path)
      unless %w[pdf printed].include?(basis)
        raise ResolutionError, "Cannot emit source for #{adventure_id}: source registry must declare page_basis as 'pdf' or 'printed'; refusing to guess"
      end
      raise ResolutionError, "Cannot emit source for #{adventure_id}: missing start/end page" unless start_page && end_page

      marker_name = basis == "pdf" ? "PDF Page" : "Printed Page"
      start_marker = "<!-- #{marker_name} #{start_page + offset} -->"
      end_marker = "<!-- #{marker_name} #{end_page + offset + 1} -->"

      text = File.read(path)
      start_idx = text.index(start_marker)
      raise ResolutionError, "Start marker not found for #{adventure_id}: #{start_marker}" unless start_idx
      end_idx = text.index(end_marker, start_idx + start_marker.length) || text.length
      text[start_idx...end_idx].rstrip + "\n"
    end

    private

    def integer_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
