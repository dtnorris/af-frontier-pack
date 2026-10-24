# frozen_string_literal: true

require "pathname"

module AfFrontier
  module Paths
    module_function

    DEFAULT_PROJECT_ROOT = "/Users/davidnorris/code"

    def project_root
      Pathname.new(ENV.fetch("AF_PROJECT_ROOT", DEFAULT_PROJECT_ROOT)).expand_path
    end

    def repo_root
      Pathname.new(File.expand_path("../..", __dir__))
    end

    def output_root
      Pathname.new(ENV.fetch("AF_FRONTIER_OUTPUT", repo_root.join("output/frontier-pack").to_s)).expand_path
    end

    # Returns the manifest path in the currently verified generation; raises
    # IntegrityError if the pack is unavailable. Retain a Pack for multiple reads.
    def manifest_path
      Pathname.new(Pack.new(root: output_root).artifact_root).join("manifest.json")
    end

    # Returns the current verified adventures path, or raises IntegrityError.
    def adventures_path
      Pathname.new(Pack.new(root: output_root).artifact_root).join("adventures.jsonl")
    end

    # Returns the current verified sources path, or raises IntegrityError.
    def sources_path
      Pathname.new(Pack.new(root: output_root).artifact_root).join("sources.jsonl")
    end

    def bundles_root
      output_root.join("bundles")
    end
  end
end
