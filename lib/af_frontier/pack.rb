# frozen_string_literal: true

require "json"

module AfFrontier
  class Pack
    attr_reader :root

    def initialize(root: Paths.output_root)
      @root = File.expand_path(root)
    end

    def manifest
      @manifest ||= JSON.parse(File.read(File.join(root, "manifest.json")))
    rescue Errno::ENOENT
      raise IntegrityError, "Frontier pack not found at #{root}; run 'bin/af-frontier build' first"
    end

    def adventures
      @adventures ||= Jsonl.read(File.join(root, "adventures.jsonl")).to_a
    end

    def sources
      @sources ||= Jsonl.read(File.join(root, "sources.jsonl")).to_a
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
  end
end
