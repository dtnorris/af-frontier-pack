# frozen_string_literal: true

require "json"
require "digest"

module AfFrontier
  # Holds one verified generation, independent of later builds at the same root.
  class Pack
    attr_reader :root, :artifact_root

    # Binds root's CURRENT once and loads its verified artifacts. Raises
    # IntegrityError for legacy, incomplete, malformed or corrupt packs.
    def initialize(root: Paths.output_root)
      @root = File.expand_path(root)
      pointer = JSON.parse(File.binread(File.join(@root, "CURRENT")))
      unless pointer.is_a?(Hash) && pointer["generation"].is_a?(String) &&
          pointer["generation"].match?(/\Ageneration-[a-zA-Z0-9_-]+\z/)
        raise IntegrityError, "Invalid frontier pack CURRENT at #{@root}"
      end
      @artifact_root = File.join(File.realpath(@root), "generations", pointer.fetch("generation"))
      unless File.realpath(@artifact_root) == @artifact_root
        raise IntegrityError, "Frontier pack generation must not be a symlink: #{@artifact_root}"
      end
      content = File.binread(File.join(@artifact_root, "manifest.json"))
      verify_hash(content, pointer["manifest_sha256"], "manifest.json")
      @manifest = JSON.parse(content)
      unless @manifest.is_a?(Hash) && @manifest["frontier_pack_schema"] == PACK_SCHEMA_VERSION &&
          @manifest["artifacts"].is_a?(Hash)
        raise IntegrityError, "Invalid frontier pack manifest at #{@artifact_root}"
      end
      @adventures = read_artifact("adventures.jsonl")
      @sources = read_artifact("sources.jsonl")
      unless @manifest["counts"].is_a?(Hash) &&
          @manifest.dig("counts", "adventures") == @adventures.length &&
          @manifest.dig("counts", "sources") == @sources.length
        raise IntegrityError, "Frontier pack artifact count mismatch at #{@artifact_root}"
      end
    rescue SystemCallError, JSON::ParserError => error
      raise IntegrityError, "Frontier pack unavailable at #{@root}; rebuild with 'bin/af-frontier build': #{error.message}"
    end

    # Returns this reader's verified manifest without rereading CURRENT.
    def manifest
      @manifest
    end

    # Returns the adventure records verified when this reader was bound.
    def adventures
      @adventures
    end

    # Returns the source records verified when this reader was bound.
    def sources
      @sources
    end

    def fetch(adventure_id)
      adventure = adventures.find { |row| row["adventure_id"] == adventure_id }
      raise ResolutionError, "Adventure ID not found in frontier pack: #{adventure_id}" unless adventure
      adventure
    end

    def authority_label
      amc = manifest.dig("inputs", "amc") || {}
      label = amc["version"] || amc["filename"] || "unknown AMC"
      sha = amc["sha256"].to_s
      sha.empty? ? label : "#{label} (sha256: #{sha[0, 12]}…)"
    end

    private

    # Returns records whose exact bytes match the manifest's named artifact hash.
    # Raises IntegrityError for absent hashes, invalid JSONL or non-object records.
    def read_artifact(name)
      descriptor = @manifest.fetch("artifacts")[name]
      sha = descriptor["sha256"] if descriptor.is_a?(Hash)
      unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{64}\z/)
        raise IntegrityError, "Missing or invalid artifact hash: #{name}"
      end
      records = Jsonl.read(File.join(@artifact_root, name), sha256: sha).to_a
      raise IntegrityError, "Invalid records in #{name}" unless records.all? { |record| record.is_a?(Hash) }
      records
    end

    # Validates a required SHA-256 and compares exact bytes.
    # Returns nil on success; raises IntegrityError for missing or mismatched hashes.
    def verify_hash(content, expected, name)
      unless expected.is_a?(String) && expected.match?(/\A[0-9a-f]{64}\z/)
        raise IntegrityError, "Missing or invalid artifact hash: #{name}"
      end
      unless Digest::SHA256.hexdigest(content) == expected
        raise IntegrityError, "Artifact hash mismatch: #{name}"
      end
      nil
    end
  end
end
