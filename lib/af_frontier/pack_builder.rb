# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"

module AfFrontier
  class PackBuilder
    ACRONYMS = %w[NoS CE EE SIE IE PPSE TC LFS RSMD SO CPA SR DHI FW GMPB GMID PBS GMBS].freeze

    def initialize(amc_path:, source_registry:, afao_path:, output_root: Paths.output_root)
      @amc_path = Pathname.new(amc_path).expand_path.realpath
      @source_registry = source_registry
      @afao_path = Pathname.new(afao_path).expand_path
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

        source_book = row["Source Book"].to_s.strip
        start_page = integer_or_nil(row["Start Page"])
        end_page = integer_or_nil(row["End Page"])
        source_resolution = @source_registry.resolve(
          source_book,
          start_page: start_page,
          end_page: end_page
        )
        unresolved_sources << source_book unless source_resolution
        adventure_record(row, source_resolution)
      end.sort_by { |record| record.fetch("adventure_id") }

      source_records = build_source_records(adventures)

      FileUtils.mkdir_p(@output_root.join("bundles"))
      Jsonl.write(@output_root.join("adventures.jsonl"), adventures)
      Jsonl.write(@output_root.join("sources.jsonl"), source_records)

      manifest = build_manifest(adventures, source_records, unresolved_sources.uniq.sort)
      File.write(@output_root.join("manifest.json"), JSON.pretty_generate(manifest) + "\n")
      manifest
    end

    private

    def adventure_record(row, source_resolution)
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

      source_book = null_if_blank(row["Source Book"])
      start_page = scalar(row["Start Page"])
      end_page = scalar(row["End Page"])

      {
        "adventure_id" => row.fetch("ADV - ID").to_s.strip,
        "title" => null_if_blank(row["Adventure Title"]),
        "source" => {
          "source_id" => source_book,
          "book" => source_book,
          "publisher" => null_if_blank(row["Book Publisher"]),
          "start_page" => start_page,
          "end_page" => end_page,
          "page_count" => scalar(row["Page Count"])
        },
        "played" => normalize_played(row["Played"]),
        "assessments" => assessments,
        "assessment_status" => {
          "assessed" => assessed,
          "unassessed" => all - assessed
        },
        # Parentage is intentionally null in v0.1. Frozen boundary artifacts preserve
        # some canonical parent edges, but there is not yet a consolidated current-state
        # parentage authority spanning the full AMC.
        "parentage" => nil,
        "source_locator" => source_locator(source_book, start_page, end_page, source_resolution)
      }
    end

    def source_locator(source_book, start_page, end_page, resolution)
      {
        "source_id" => source_book,
        "path" => resolution&.markdown_path,
        "start_page" => start_page,
        "end_page" => end_page,
        "strategy" => resolution&.strategy,
        "warnings" => resolution&.warnings || [],
        "page_marker_offset" => resolution&.page_marker_offset,
        "segment_start_page" => resolution&.segment_start_page,
        "segment_end_page" => resolution&.segment_end_page
      }.compact
    end

    def build_source_records(adventures)
      adventures.group_by { |adventure| adventure.dig("source", "source_id") }
        .sort_by { |source_id, _| source_id.to_s }
        .map do |source_id, source_adventures|
          publishers = source_adventures.filter_map { |adventure| adventure.dig("source", "publisher") }.uniq.sort
          locators = source_adventures.filter_map do |adventure|
            locator = adventure.fetch("source_locator")
            next unless locator["path"]

            {
              "path" => locator.fetch("path"),
              "strategy" => locator["strategy"],
              "warnings" => locator["warnings"] || [],
              "page_marker_offset" => locator.fetch("page_marker_offset", 0),
              "segment_start_page" => locator["segment_start_page"],
              "segment_end_page" => locator["segment_end_page"],
              "content_sha256" => Digest::SHA256.file(locator.fetch("path")).hexdigest
            }.compact
          end.uniq { |locator| [locator["path"], locator["page_marker_offset"], locator["segment_start_page"], locator["segment_end_page"]] }
            .sort_by { |locator| [locator["segment_start_page"] || -1, locator["path"]] }

          resolved_count = source_adventures.count { |adventure| adventure.dig("source_locator", "path") }
          status = if resolved_count.zero?
            "unresolved"
          elsif resolved_count == source_adventures.length
            "resolved"
          else
            "partial"
          end

          {
            "source_id" => source_id,
            "title" => source_id,
            "publishers" => publishers,
            "resolution_status" => status,
            "adventure_count" => source_adventures.length,
            "resolved_adventure_count" => resolved_count,
            "markdown_locators" => locators
          }
        end
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
            "sha256" => amc_sha,
            "bytes" => @amc_path.size
          },
          "afao" => afao_descriptor,
          "source_registry" => {
            "path" => @source_registry.path.to_s,
            "schema_version" => SourceRegistry::REGISTRY_SCHEMA_VERSION,
            "sha256" => @source_registry.sha256
          }
        },
        "counts" => {
          "adventures" => adventures.length,
          "sources" => sources.length,
          "source_resolved" => adventures.count { |adventure| adventure.dig("source_locator", "path") },
          "source_unresolved" => adventures.count { |adventure| adventure.dig("source_locator", "path").nil? }
        },
        "unresolved_source_books" => unresolved
      }
    end

    def afao_descriptor
      raise ConfigurationError, "AFAO file does not exist: #{@afao_path}" unless @afao_path.file?

      realpath = @afao_path.realpath
      {
        "filename" => realpath.basename.to_s,
        "path" => realpath.to_s,
        "version" => AnalysisOntologyResolver.detect_version(realpath),
        "sha256" => Digest::SHA256.file(realpath).hexdigest,
        "bytes" => realpath.size
      }
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

    def integer_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def null_if_blank(value)
      return nil if value.nil? || value.to_s.strip.empty?
      value.to_s.strip
    end
  end
end
