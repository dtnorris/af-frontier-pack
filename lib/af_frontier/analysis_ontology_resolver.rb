# frozen_string_literal: true

require "yaml"
require "pathname"
require "digest"

module AfFrontier
  class AnalysisOntologyResolver
    VERSION_HEADING_RE = /^##\s+Version\s+([^\s]+)\s*$/i

    # Reviewed SP-03 inventory identity, independent of the supplied file's bytes.
    # Only this AFAO is needed; its Candidate status does not imply acceptance.
    PUBLIC_AFAO = {
      "repository" => "https://github.com/dtnorris/af-specification-md",
      "revision" => "394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf",
      "path" => "AdventureFinder_Analysis_Ontology_AFAO_v1.6.1.md",
      "version" => "1.6.1",
      "sha256" => "dcfad224ab9517272504a508f935a804032d04a7c812ede10498921ce4585fa1",
      "bytes" => 339101
    }.freeze

    Resolution = Struct.new(
      :path, :source, :version, :sha256, :bytes, :public_specification, keyword_init: true
    )

    def self.detect_version(path)
      path = Pathname.new(path)
      match = File.read(path, encoding: "UTF-8").match(VERSION_HEADING_RE)
      raise ResolutionError, "Unable to detect AFAO version in #{path}" unless match

      match[1]
    end

    # Stores optional root/config locators; an explicit ontology needs no root.
    # Required authority failures are reported by resolve, not construction.
    def initialize(
      project_root: nil,
      authority_config: Paths.repo_root.join("config/authority.yml")
    )
      @project_root = project_root
      @authority_config = Pathname.new(authority_config).expand_path
    end

    # Returns historical explicit input or the selected configured/public authority.
    # Explicit paths are cwd-relative. Public selections enforce the reviewed pin;
    # conflicting, missing or invalid inputs raise ResolutionError/ConfigurationError.
    def resolve(explicit_afao: nil, public_afao: nil)
      if !explicit_afao.nil? && !public_afao.nil?
        raise ConfigurationError, "Select only one of --afao and --public-afao"
      end
      return resolution_for(explicit_afao, "--afao") unless explicit_afao.nil?
      return public_resolution(public_afao, "--public-afao") unless public_afao.nil?

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
      path = Paths.project_root(@project_root).join(path) unless path.absolute?
      if entry["selection"] == "public"
        unless expected_version == PUBLIC_AFAO.fetch("version")
          raise ResolutionError, "Configured public AFAO version must be #{PUBLIC_AFAO.fetch('version')}"
        end
        return public_resolution(path, @authority_config.realpath.to_s)
      end
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

    # Validates a public locator against the fixed source revision's filename,
    # declared version, digest and size; returns provenance or raises ResolutionError.
    def public_resolution(value, source)
      resolution = resolution_for(value, source)
      expected = PUBLIC_AFAO
      unless resolution.path.basename.to_s == expected.fetch("path")
        raise ResolutionError, "Public AFAO filename mismatch: expected #{expected.fetch('path')}"
      end
      unless resolution.version == expected.fetch("version")
        raise ResolutionError, "Public AFAO version mismatch: expected #{expected.fetch('version')}, file declares #{resolution.version}"
      end
      unless resolution.sha256 == expected.fetch("sha256") && resolution.bytes == expected.fetch("bytes")
        raise ResolutionError, "Public AFAO content mismatch for #{expected.fetch('revision')}: #{resolution.path}"
      end
      resolution.public_specification = expected.slice("repository", "revision", "path")
      resolution
    end

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
  end
end
