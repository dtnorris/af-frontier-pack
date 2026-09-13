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

    def manifest_path
      output_root.join("manifest.json")
    end

    def adventures_path
      output_root.join("adventures.jsonl")
    end

    def sources_path
      output_root.join("sources.jsonl")
    end

    def bundles_root
      output_root.join("bundles")
    end
  end
end
