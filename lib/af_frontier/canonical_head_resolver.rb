# frozen_string_literal: true

require "yaml"
require "pathname"
require "digest"

module AfFrontier
  class CanonicalHeadResolver
    PROJECT_STATE_SCHEMA = "adventurefinder-project-state/v0.1"
    AMC_FILENAME_RE = /\A5e_Adventure_Master_Catalog_(?<version>\d+(?:\.\d+)*)\.xlsx\z/

    Resolution = Struct.new(
      :path, :source, :role, :version, :sha256, :bytes, keyword_init: true
    )

    def initialize(project_root: Paths.project_root, authority_config: Paths.repo_root.join("config/authority.yml"))
      @project_root = Pathname.new(project_root).expand_path
      @authority_config = Pathname.new(authority_config)
    end

    def resolve(explicit_amc: nil, state_path: nil)
      return explicit_resolution(explicit_amc, "--amc") if present?(explicit_amc)
      return explicit_resolution(ENV["AF_FRONTIER_AMC"], "AF_FRONTIER_AMC") if present?(ENV["AF_FRONTIER_AMC"])

      config = load_authority_config
      role = config.fetch("role", "catalog_head")
      expected_schema = config.fetch("schema_version", PROJECT_STATE_SCHEMA)
      manifests = state_path ? [Pathname.new(state_path).expand_path] : configured_manifests(config)

      manifests.each do |manifest|
        next unless manifest.file?
        return resolve_from_manifest(manifest, role, expected_schema)
      end

      raise ResolutionError, <<~MSG.strip
        Could not resolve authoritative #{role.inspect}.
        Supply --amc PATH, set AF_FRONTIER_AMC, or provide --state PATH using #{expected_schema}.
        af-frontier intentionally does not infer canonicality from the numerically largest AMC filename.
      MSG
    end

    private

    def explicit_resolution(value, source)
      path = Pathname.new(value).expand_path
      raise ResolutionError, "AMC from #{source} does not exist: #{path}" unless path.file?

      realpath = path.realpath
      Resolution.new(
        path: realpath,
        source: source,
        role: "explicit",
        version: version_from_filename(realpath.basename.to_s),
        sha256: Digest::SHA256.file(realpath).hexdigest,
        bytes: realpath.size
      )
    end

    def resolve_from_manifest(manifest, role, expected_schema)
      data = YAML.safe_load(manifest.read, permitted_classes: [], aliases: false) || {}
      unless data.is_a?(Hash) && data["schema_version"] == expected_schema
        actual = data.is_a?(Hash) ? data["schema_version"] : nil
        raise ResolutionError,
              "Unsupported project-state schema #{actual.inspect} in #{manifest}; expected #{expected_schema.inspect}"
      end

      entry = data[role]
      raise ResolutionError, "Project state #{manifest} is missing role #{role.inspect}" unless entry.is_a?(Hash)

      version = entry["version"].to_s.strip
      filename = entry["filename"].to_s.strip
      expected_sha = entry["sha256"].to_s.strip.downcase
      expected_bytes = entry["bytes"]
      validate_entry!(role, version, filename, expected_sha, expected_bytes)

      path = manifest.dirname.join(filename)
      raise ResolutionError, "#{role} in #{manifest} points to missing AMC: #{path}" unless path.file?

      actual_bytes = path.size
      unless actual_bytes == expected_bytes
        raise ResolutionError,
              "#{role} catalog byte-size mismatch: expected #{expected_bytes}, got #{actual_bytes}: #{path}"
      end

      actual_sha = Digest::SHA256.file(path).hexdigest
      unless actual_sha == expected_sha
        raise ResolutionError,
              "#{role} catalog SHA-256 mismatch: expected #{expected_sha}, got #{actual_sha}: #{path}"
      end

      Resolution.new(
        path: path.realpath,
        source: manifest.realpath.to_s,
        role: role,
        version: version,
        sha256: actual_sha,
        bytes: actual_bytes
      )
    rescue Psych::Exception => e
      raise ResolutionError, "Could not parse state manifest #{manifest}: #{e.message}"
    end

    def validate_entry!(role, version, filename, sha, bytes)
      if version.empty? || sha !~ /\A[0-9a-f]{64}\z/ || !bytes.is_a?(Integer) || bytes <= 0
        raise ResolutionError, "Invalid project-state entry for #{role.inspect}"
      end

      expected_filename = "5e_Adventure_Master_Catalog_#{version}.xlsx"
      unless filename == expected_filename && File.basename(filename) == filename
        raise ResolutionError,
              "Invalid project-state filename for #{role.inspect}: #{filename.inspect}; expected #{expected_filename.inspect}"
      end
    end

    def configured_manifests(config)
      Array(config["state_manifests"]).map do |value|
        path = Pathname.new(value)
        path.absolute? ? path : @project_root.join(path)
      end
    end

    def load_authority_config
      return {} unless @authority_config.file?
      YAML.safe_load(@authority_config.read, permitted_classes: [], aliases: false) || {}
    rescue Psych::Exception => e
      raise ConfigurationError, "Could not parse authority config #{@authority_config}: #{e.message}"
    end

    def version_from_filename(filename)
      AMC_FILENAME_RE.match(filename)&.[](:version)
    end

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
