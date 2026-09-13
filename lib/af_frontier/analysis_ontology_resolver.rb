# frozen_string_literal: true

require "yaml"
require "pathname"
require "digest"

module AfFrontier
  class AnalysisOntologyResolver
    VERSION_HEADING_RE = /^##\s+Version\s+([^\s]+)\s*$/i

    Resolution = Struct.new(
      :path, :source, :version, :sha256, :bytes, keyword_init: true
    )

    def self.detect_version(path)
      path = Pathname.new(path)
      match = File.read(path, encoding: "UTF-8").match(VERSION_HEADING_RE)
      raise ResolutionError, "Unable to detect AFAO version in #{path}" unless match

      match[1]
    end

    def initialize(
      project_root: Paths.project_root,
      authority_config: Paths.repo_root.join("config/authority.yml")
    )
      @project_root = Pathname.new(project_root).expand_path
      @authority_config = Pathname.new(authority_config).expand_path
    end

    def resolve(explicit_afao: nil)
      return resolution_for(explicit_afao, "--afao") if present?(explicit_afao)

      config = load_authority_config
      entry = config["afao"]
      unless entry.is_a?(Hash)
        raise ResolutionError, "Authority config #{@authority_config} is missing afao contract"
      end

      configured_path = entry["path"].to_s.strip
      expected_version = entry["version"].to_s.strip
      if configured_path.empty? || expected_version.empty?
        raise ResolutionError, "Invalid afao contract in #{@authority_config}"
      end

      path = Pathname.new(configured_path)
      path = @project_root.join(path) unless path.absolute?
      resolution = resolution_for(path, @authority_config.realpath.to_s)

      expected_filename = "AdventureFinder_Analysis_Ontology_v#{expected_version}.md"
      unless resolution.path.basename.to_s == expected_filename
        raise ResolutionError,
              "Configured AFAO filename mismatch: expected #{expected_filename.inspect}, " \
              "got #{resolution.path.basename}"
      end

      unless resolution.version == expected_version
        raise ResolutionError,
              "Configured AFAO version mismatch: expected #{expected_version}, " \
              "file declares #{resolution.version}: #{resolution.path}"
      end

      resolution
    end

    private

    def resolution_for(value, source)
      path = Pathname.new(value).expand_path
      raise ResolutionError, "AFAO from #{source} does not exist: #{path}" unless path.file?

      realpath = path.realpath
      Resolution.new(
        path: realpath,
        source: source,
        version: self.class.detect_version(realpath),
        sha256: Digest::SHA256.file(realpath).hexdigest,
        bytes: realpath.size
      )
    end

    def load_authority_config
      unless @authority_config.file?
        raise ConfigurationError, "Authority config not found: #{@authority_config}"
      end

      YAML.safe_load(@authority_config.read, permitted_classes: [], aliases: false) || {}
    rescue Psych::Exception => e
      raise ConfigurationError, "Could not parse authority config #{@authority_config}: #{e.message}"
    end

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
