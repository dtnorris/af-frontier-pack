# frozen_string_literal: true

module AfFrontier
  class SourceResolver
    PRINTED_PAGE_MARKER = /^\s*(?:>\s*)*<!--\s*Printed\s+Page\s+(\d+)\s*-->\s*$/i
    FALLBACK_PAGE_MARKER = /^\s*(?:>\s*)*<!--\s*(?:PDF\s+Page|PAGE:)\s*(\d+)\s*-->\s*$/i

    def initialize(pack: Pack.new)
      @pack = pack
    end

    def locator(adventure_id)
      @pack.fetch(adventure_id).fetch("source_locator")
    end

    def emit(adventure_id)
      locator = locator(adventure_id)
      path = locator["path"]
      offset = Integer(locator.fetch("page_marker_offset", 0))
      start_page = integer_or_nil(locator["start_page"])
      end_page = integer_or_nil(locator["end_page"])

      raise ResolutionError, "No canonical Markdown source resolved for #{adventure_id}" unless path && File.file?(path)
      raise ResolutionError, "Cannot emit source for #{adventure_id}: missing start/end page" unless start_page && end_page
      raise ResolutionError, "Cannot emit source for #{adventure_id}: start page exceeds end page" if start_page > end_page

      text = File.read(path, encoding: "UTF-8")
      markers = page_markers(text)
      raise ResolutionError, "No supported page markers found in #{path}" if markers.empty?

      marker_start_page = start_page + offset
      marker_end_page = end_page + offset
      start_marker = markers.find { |marker| marker[:page] == marker_start_page }
      end_marker_index = markers.index { |marker| marker[:page] == marker_end_page }

      unless start_marker && end_marker_index
        missing = []
        missing << marker_start_page unless start_marker
        missing << marker_end_page unless end_marker_index
        raise ResolutionError,
              "Required source page marker(s) not found for #{adventure_id}: #{missing.uniq.join(', ')} " \
              "(canonical #{start_page}-#{end_page}, page_marker_offset #{format('%+d', offset)})"
      end

      start_offset = start_marker.fetch(:offset)
      following = markers[end_marker_index + 1]
      end_offset = following ? following.fetch(:offset) : text.bytesize
      if end_offset <= start_offset
        raise ResolutionError,
              "Page marker ordering is inconsistent for #{adventure_id}: #{marker_start_page}-#{marker_end_page}"
      end

      text.byteslice(start_offset...end_offset).rstrip + "\n"
    end

    private

    def page_markers(text)
      printed = markers_for(text, PRINTED_PAGE_MARKER)
      printed.empty? ? markers_for(text, FALLBACK_PAGE_MARKER) : printed
    end

    def markers_for(text, pattern)
      markers = []
      cursor = 0
      text.each_line do |line|
        if (match = line.match(pattern))
          markers << { page: match[1].to_i, offset: cursor }
        end
        cursor += line.bytesize
      end
      markers
    end

    def integer_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
