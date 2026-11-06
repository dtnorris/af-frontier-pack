# frozen_string_literal: true

require "pathname"

module AfFrontier
  module Paths
    module_function

    # Returns a deliberately configured root for relative build defaults. An
    # optional resolver root overrides the environment. Raises ConfigurationError
    # for missing, blank or nonexistent directories; never discovers cwd/home.
    def project_root(value = nil)
      value = ENV["AF_PROJECT_ROOT"] if value.nil?
      if value.to_s.strip.empty?
        raise ConfigurationError,
              "AF_PROJECT_ROOT is unconfigured. Set it to an existing library layout directory, " \
              "or supply --state (or --amc), --afao and --corpus-root explicitly."
      end

      root = Pathname.new(value).expand_path
      raise ConfigurationError, "AF_PROJECT_ROOT must be an existing directory: #{root}" unless root.directory?

      root
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
