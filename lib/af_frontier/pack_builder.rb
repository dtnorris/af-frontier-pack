# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"
require "tmpdir"
require "tempfile"

module AfFrontier
  # Builds validated catalog snapshots and publishes each through one CURRENT rename.
  class PackBuilder
    ACRONYMS = %w[NoS CE EE SIE IE PPSE TC LFS RSMD SO CPA SR DHI FW GMPB GMID PBS GMBS].freeze

    # Store selected inputs and output, with an optional private source
    # declaration. Missing AMC raises filesystem errors.
    def initialize(amc_path:, source_registry:, afao_path:, output_root: Paths.output_root, public_afao: false,
                   reviewed_source_path: nil)
      @amc_path = Pathname.new(amc_path).expand_path.realpath
      @source_registry = source_registry
      @reviewed_source_path = reviewed_source_path
      @afao_path = Pathname.new(afao_path).expand_path
      @public_afao = public_afao
      @output_root = Pathname.new(output_root).expand_path
    end

    # Returns the deterministic manifest for the supplied authorities. Validation or
    # filesystem errors before CURRENT replacement leave the previous pack selected.
    def build
      review = ReviewedSource.new(@reviewed_source_path) if @reviewed_source_path
      rows = XlsxCatalogReader.new(@amc_path).rows
      if review && rows.none? { |row| row.fetch("ADV - ID").to_s.strip == review.adventure_id }
        raise ResolutionError, "Reviewed source Adventure ID not found in catalog: #{review.adventure_id}"
      end
      seen = {}
      unresolved_sources = []

      adventures = rows.map do |row|
        adv_id = row.fetch("ADV - ID").to_s.strip
        raise IntegrityError, "Duplicate Adventure ID in AMC: #{adv_id}" if seen[adv_id]
        seen[adv_id] = true

        source_book = row["Source Book"].to_s.strip
        start_page = integer_or_nil(row["Start Page"])
        end_page = integer_or_nil(row["End Page"])
        reviewed_locator = review.locator_for(row, registry: @source_registry) if review&.adventure_id == adv_id
        source_resolution = @source_registry.resolve(source_book, start_page:, end_page:) unless reviewed_locator
        unresolved_sources << source_book unless source_resolution
        adventure_record(row, source_resolution, reviewed_locator:)
      end.sort_by { |record| record.fetch("adventure_id") }

      source_records = build_source_records(adventures)

      manifest = build_manifest(adventures, source_records, unresolved_sources.uniq.sort)
      # Reuse the existing integrity rules before making any new pack visible.
      snapshot = Struct.new(:manifest, :adventures, :sources).new(manifest, adventures, source_records)
      Doctor.new(pack: snapshot).check
      publish(manifest, adventures, source_records)
      manifest
    end

    private

    # Writes complete private artifacts and their hashes, then atomically replaces
    # CURRENT. Raises filesystem errors; published directories are never reclaimed
    # here because readers and other writers may still need them.
    def publish(manifest, adventures, sources)
      generations = @output_root.join("generations")
      FileUtils.mkdir_p(generations)
      FileUtils.mkdir_p(@output_root.join("bundles"))
      staging = Dir.mktmpdir(".building-", generations.to_s)
      begin
        Jsonl.write(File.join(staging, "adventures.jsonl"), adventures)
        Jsonl.write(File.join(staging, "sources.jsonl"), sources)
        manifest["artifacts"] = %w[adventures.jsonl sources.jsonl].to_h do |name|
          [name, { "sha256" => Digest::SHA256.file(File.join(staging, name)).hexdigest }]
        end
        manifest_bytes = JSON.pretty_generate(manifest) + "\n"
        File.write(File.join(staging, "manifest.json"), manifest_bytes)
        generation = File.basename(staging).sub(".building-", "generation-")
        File.rename(staging, generations.join(generation))
        pointer = { "generation" => generation, "manifest_sha256" => Digest::SHA256.hexdigest(manifest_bytes) }
        Tempfile.create([".CURRENT-", ".json"], @output_root.to_s) do |file|
          file.write(JSON.generate(pointer) + "\n")
          file.close
          File.rename(file.path, @output_root.join("CURRENT"))
        end
      ensure
        FileUtils.rm_rf(staging)
      end
    end

    # Return the catalog row with its ordinary or reviewed locator. The row
    # must carry the Adventure ID supplied by the catalog reader.
    def adventure_record(row, source_resolution, reviewed_locator:)
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
        "source_locator" => reviewed_locator || source_locator(source_book, start_page, end_page, source_resolution)
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

    # Index the pack's ordinary and reviewed file references by catalog source.
    # Reading an ordinary locator's source bytes can raise filesystem errors.
    def build_source_records(adventures)
      adventures.group_by { |adventure| adventure.dig("source", "source_id") }
        .sort_by { |source_id, _| source_id.to_s }
        .map do |source_id, source_adventures|
          publishers = source_adventures.filter_map { |adventure| adventure.dig("source", "publisher") }.uniq.sort
          locators = source_adventures.flat_map do |adventure|
            locator = adventure.fetch("source_locator")
            next locator.fetch("source_references", []) unless locator["path"]

            [{
              "path" => locator.fetch("path"),
              "strategy" => locator["strategy"],
              "warnings" => locator["warnings"] || [],
              "page_marker_offset" => locator.fetch("page_marker_offset", 0),
              "segment_start_page" => locator["segment_start_page"],
              "segment_end_page" => locator["segment_end_page"],
              "content_sha256" => Digest::SHA256.file(locator.fetch("path")).hexdigest
            }.compact]
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

    # Returns the consumed ontology's descriptor, retaining historical input behavior.
    # Public input is revalidated here so a post-resolution edit cannot be rehashed
    # into validity. Missing/changed authority raises ConfigurationError/ResolutionError.
    def afao_descriptor
      raise ConfigurationError, "AFAO file does not exist: #{@afao_path}" unless @afao_path.file?

      realpath = @afao_path.realpath
      resolver = AnalysisOntologyResolver.new
      resolution = @public_afao ? resolver.resolve(public_afao: realpath) : resolver.resolve(explicit_afao: realpath)
      descriptor = {
        "filename" => realpath.basename.to_s,
        "path" => realpath.to_s,
        "version" => resolution.version,
        "sha256" => resolution.sha256,
        "bytes" => resolution.bytes
      }
      if resolution.public_specification
        descriptor["public_specification"] = resolution.public_specification
      end
      descriptor
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
