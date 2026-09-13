# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"

module AfFrontier
  class PackBuilder
    ACRONYMS = %w[NoS CE EE SIE IE PPSE TC LFS RSMD SO CPA SR DHI FW GMPB GMID PBS GMBS].freeze

    def initialize(amc_path:, source_registry:, afao_path: nil, output_root: Paths.output_root)
      @amc_path = Pathname.new(amc_path).expand_path.realpath
      @source_registry = source_registry
      @afao_path = afao_path && Pathname.new(afao_path).expand_path
      @output_root = Pathname.new(output_root).expand_path
    end

    def build
      rows = XlsxCatalogReader.new(@amc_path).rows
      seen = {}
      unresolved_sources = []

      adventures = rows.map do |row|
        adv_id = row.fetch("ADV - ID").to_s.strip
        raise IntegrityError, "Duplicate Adventure ID in AMC: #{adv_id}" if seen[adv_id]
        seen[adv_id] = true

        source_entry = @source_registry.resolve(row["Source Book"].to_s)
        unresolved_sources << row["Source Book"].to_s unless source_entry
        adventure_record(row, source_entry)
      end.sort_by { |r| r.fetch("adventure_id") }

      source_records = @source_registry.entries
        .select { |entry| adventures.any? { |adv| adv.dig("source", "source_id") == entry.source_id } }
        .sort_by(&:source_id)
        .map { |entry| source_record(entry) }

      FileUtils.mkdir_p(@output_root.join("bundles"))
      Jsonl.write(@output_root.join("adventures.jsonl"), adventures)
      Jsonl.write(@output_root.join("sources.jsonl"), source_records)

      manifest = build_manifest(adventures, source_records, unresolved_sources.uniq.sort)
      File.write(@output_root.join("manifest.json"), JSON.pretty_generate(manifest) + "\n")
      manifest
    end

    private

    def adventure_record(row, source_entry)
      assessments = {
        "NoS" => scalar(row["Number of Sessions"]),
        "LSLE" => {
          "start" => scalar(row["Level Start"]),
          "end" => scalar(row["Level End"])
        }
      }
      XlsxCatalogReader::DIMENSION_HEADERS.each do |acronym, header|
        next if acronym == "NoS"
        assessments[acronym] = scalar(row[header])
      end

      assessed = assessments.flat_map do |key, value|
        if key == "LSLE"
          value["start"].nil? && value["end"].nil? ? [] : [key]
        else
          value.nil? ? [] : [key]
        end
      end
      all = ["NoS", "LSLE"] + (ACRONYMS - ["NoS"])

      source_id = source_entry&.source_id
      source_path = source_entry&.markdown_path

      {
        "adventure_id" => row.fetch("ADV - ID").to_s.strip,
        "title" => null_if_blank(row["Adventure Title"]),
        "source" => {
          "source_id" => source_id,
          "book" => null_if_blank(row["Source Book"]),
          "publisher" => null_if_blank(row["Book Publisher"] || source_entry&.publisher),
          "start_page" => scalar(row["Start Page"]),
          "end_page" => scalar(row["End Page"]),
          "page_count" => scalar(row["Page Count"])
        },
        "played" => normalize_played(row["Played"]),
        "assessments" => assessments,
        "assessment_status" => {
          "assessed" => assessed,
          "unassessed" => all - assessed
        },
        "parentage" => nil,
        "source_locator" => {
          "source_id" => source_id,
          "path" => source_path,
          "start_page" => scalar(row["Start Page"]),
          "end_page" => scalar(row["End Page"]),
          "page_basis" => source_entry&.page_basis,
          "page_offset" => source_entry&.page_offset
        }
      }
    end

    def source_record(entry)
      hash = entry.to_h
      path = entry.markdown_path
      hash["content_sha256"] = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
      hash
    end

    def build_manifest(adventures, sources, unresolved)
      amc_sha = Digest::SHA256.file(@amc_path).hexdigest
      {
        "frontier_pack_schema" => PACK_SCHEMA_VERSION,
        "generator_version" => VERSION,
        "inputs" => {
          "amc" => {
            "filename" => @amc_path.basename.to_s,
            "path" => @amc_path.to_s,
            "version" => extract_version(@amc_path.basename.to_s),
            "sha256" => amc_sha
          },
          "afao" => file_descriptor(@afao_path),
          "source_registry" => {
            "path" => @source_registry.path.to_s,
            "sha256" => @source_registry.sha256
          }
        },
        "counts" => {
          "adventures" => adventures.length,
          "sources" => sources.length,
          "source_resolved" => adventures.count { |a| a.dig("source_locator", "path") },
          "source_unresolved" => adventures.count { |a| a.dig("source_locator", "path").nil? }
        },
        "unresolved_source_books" => unresolved
      }
    end

    def file_descriptor(path)
      return nil unless path
      raise ConfigurationError, "AFAO file does not exist: #{path}" unless path.file?
      { "path" => path.realpath.to_s, "sha256" => Digest::SHA256.file(path).hexdigest }
    end

    def extract_version(filename)
      filename[/Adventure_Master_Catalog_([0-9]+(?:\.[0-9]+)*)/i, 1]
    end

    def normalize_played(value)
      return nil if value.nil? || value.to_s.strip.empty?
      return value if value == true || value == false
      str = value.to_s.strip.downcase
      return true if %w[1 true yes y played].include?(str)
      return false if %w[0 false no n unplayed].include?(str)
      value
    end

    def scalar(value)
      return nil if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      value
    end

    def null_if_blank(value)
      return nil if value.nil? || value.to_s.strip.empty?
      value.to_s.strip
    end
  end
end
