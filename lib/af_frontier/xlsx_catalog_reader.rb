# frozen_string_literal: true

require "open3"
require "rexml/document"
require "set"

module AfFrontier
  class XlsxCatalogReader
    SHEET_NAME = "Adventure Catalog"

    DIMENSION_HEADERS = {
      "NoS" => "Number of Sessions",
      "CE" => "Combat Emphasis",
      "EE" => "Exploration Emphasis",
      "SIE" => "Social Interaction Emphasis",
      "IE" => "Investigation Emphasis",
      "PPSE" => "Puzzle / Problem-Solving Emphasis",
      "TC" => "Tactical Complexity",
      "LFS" => "Lethality / Failure Severity",
      "RSMD" => "Rules / System-Master Demand",
      "SO" => "Structural Openness",
      "CPA" => "Consequential Player Agency",
      "SR" => "Seriousness",
      "DHI" => "Darkness / Horror Intensity",
      "FW" => "Fantastic Weirdness",
      "GMPB" => "GM Preparation Burden",
      "GMID" => "GM Improvisation Demand",
      "PBS" => "Player Beginner Suitability",
      "GMBS" => "GM Beginner Suitability"
    }.freeze

    REQUIRED_HEADERS = [
      "ADV - ID", "Adventure Title", "Source Book", "Book Publisher",
      "Start Page", "End Page", "Level Start", "Level End"
    ].freeze

    def initialize(path)
      @path = File.expand_path(path)
    end

    def rows
      @rows ||= parse_rows
    end

    private

    def parse_rows
      ensure_xlsx!
      shared = shared_strings
      sheet_path = worksheet_path(SHEET_NAME)
      xml = unzip_read(sheet_path)
      doc = REXML::Document.new(xml)

      raw_rows = []
      REXML::XPath.each(doc, "//*[local-name()='sheetData']/*[local-name()='row']") do |row|
        values = {}
        row.elements.each do |cell|
          next unless cell.name.split(":").last == "c"
          ref = cell.attributes["r"]
          col = column_index(ref)
          values[col] = cell_value(cell, shared)
        end
        raw_rows << values
      end

      header_idx = raw_rows.index { |r| r.values.map(&:to_s).include?("ADV - ID") }
      raise IntegrityError, "Could not find Adventure Catalog header row containing 'ADV - ID'" unless header_idx

      headers = raw_rows[header_idx]
      index_to_header = headers.transform_values { |v| v.to_s.strip }
      present_headers = index_to_header.values.to_set
      missing = REQUIRED_HEADERS.reject { |h| present_headers.include?(h) }
      raise IntegrityError, "AMC missing required headers: #{missing.join(', ')}" unless missing.empty?

      raw_rows[(header_idx + 1)..].filter_map do |raw|
        mapped = raw.each_with_object({}) do |(idx, value), memo|
          header = index_to_header[idx]
          memo[header] = value if header && !header.empty?
        end
        adv_id = mapped["ADV - ID"].to_s.strip
        next if adv_id.empty?
        mapped
      end
    rescue REXML::ParseException => e
      raise IntegrityError, "Could not parse XLSX XML #{@path}: #{e.message}"
    end

    def ensure_xlsx!
      raise IntegrityError, "AMC does not exist: #{@path}" unless File.file?(@path)
      out, status = Open3.capture2e("unzip", "-tqq", @path)
      raise IntegrityError, "AMC is not a readable XLSX/ZIP package: #{@path}: #{out.strip}" unless status.success?
    end

    def worksheet_path(name)
      workbook = REXML::Document.new(unzip_read("xl/workbook.xml"))
      rel_id = nil
      REXML::XPath.each(workbook, "//*[local-name()='sheet']") do |sheet|
        next unless sheet.attributes["name"] == name
        rel_id = sheet.attributes["r:id"] || sheet.attributes["id"]
        break
      end
      raise IntegrityError, "Workbook has no sheet named #{name.inspect}" unless rel_id

      rels = REXML::Document.new(unzip_read("xl/_rels/workbook.xml.rels"))
      target = nil
      REXML::XPath.each(rels, "//*[local-name()='Relationship']") do |rel|
        if rel.attributes["Id"] == rel_id
          target = rel.attributes["Target"]
          break
        end
      end
      raise IntegrityError, "Could not resolve worksheet relationship #{rel_id}" unless target

      target = target.sub(%r{^/}, "")
      target.start_with?("xl/") ? target : File.join("xl", target).gsub(%r{/+}, "/")
    end

    def shared_strings
      xml = unzip_read("xl/sharedStrings.xml", optional: true)
      return [] unless xml
      doc = REXML::Document.new(xml)
      strings = []
      REXML::XPath.each(doc, "//*[local-name()='si']") do |si|
        texts = []
        REXML::XPath.each(si, ".//*[local-name()='t']") { |t| texts << (t.text || "") }
        strings << texts.join
      end
      strings
    end

    def cell_value(cell, shared)
      type = cell.attributes["t"]
      if type == "inlineStr"
        texts = []
        REXML::XPath.each(cell, ".//*[local-name()='t']") { |t| texts << (t.text || "") }
        return texts.join
      end

      value_el = REXML::XPath.first(cell, "./*[local-name()='v']")
      return nil unless value_el
      raw = value_el.text.to_s

      case type
      when "s"
        shared.fetch(raw.to_i)
      when "b"
        raw == "1"
      when "str"
        raw
      else
        numeric(raw)
      end
    end

    def numeric(raw)
      return raw.to_i if raw.match?(/\A-?\d+\z/)
      return raw.to_f if raw.match?(/\A-?(?:\d+\.\d*|\d*\.\d+)\z/)
      raw
    end

    def column_index(ref)
      letters = ref.to_s[/\A[A-Z]+/]
      raise IntegrityError, "Malformed XLSX cell reference: #{ref.inspect}" unless letters
      letters.each_byte.reduce(0) { |sum, b| (sum * 26) + (b - 64) } - 1
    end

    def unzip_read(entry, optional: false)
      out, status = Open3.capture2e("unzip", "-p", @path, entry)
      return nil if optional && !status.success?
      raise IntegrityError, "Could not read #{entry} from #{@path}: #{out.strip}" unless status.success?
      out
    end
  end
end
