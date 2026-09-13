# frozen_string_literal: true

require "yaml"
require "pathname"

module AfFrontier
  class CanonicalHeadResolver
    Resolution = Struct.new(:path, :source, :role, keyword_init: true)

    def initialize(project_root: Paths.project_root, authority_config: Paths.repo_root.join("config/authority.yml"))
      @project_root = Pathname.new(project_root).expand_path
      @authority_config = Pathname.new(authority_config)
    end

    def resolve(explicit_amc: nil, state_path: nil)
      return explicit_resolution(explicit_amc, "--amc") if present?(explicit_amc)
      return explicit_resolution(ENV["AF_FRONTIER_AMC"], "AF_FRONTIER_AMC") if present?(ENV["AF_FRONTIER_AMC"])

      config = load_authority_config
      role = config.fetch("role", "catalog_head")
      manifests = state_path ? [Pathname.new(state_path)] : Array(config["state_manifests"]).map { |p| expand_project_path(p) }

      manifests.each do |manifest|
        next unless manifest.file?
        resolved = resolve_from_manifest(manifest, role)
        return resolved if resolved
      end

      raise ResolutionError, <<~MSG.strip
        Could not resolve authoritative #{role.inspect}.
        Supply --amc PATH, set AF_FRONTIER_AMC, or provide --state PATH containing an explicit #{role} role.
        af-frontier intentionally does not infer canonicality from the numerically largest AMC filename.
      MSG
    end

    private

    def explicit_resolution(value, source)
      path = Pathname.new(value).expand_path
      raise ResolutionError, "AMC from #{source} does not exist: #{path}" unless path.file?
      Resolution.new(path: path.realpath, source: source, role: "explicit")
    end

    def resolve_from_manifest(manifest, role)
      data = YAML.safe_load(manifest.read, permitted_classes: [], aliases: false) || {}
      entry = if data.is_a?(Hash)
        data[role] || data.dig("roles", role)
      end
      return nil unless entry

      value = case entry
              when String then entry
              when Hash then entry["path"] || entry["filename"] || entry["file"]
              end
      return nil unless present?(value)

      path = Pathname.new(value)
      path = if path.absolute?
        path
      elsif entry.is_a?(Hash) && present?(entry["repository"])
        @project_root.join(entry["repository"], path)
      else
        # Prefer path relative to the state manifest itself when it exists there;
        # otherwise resolve from the AdventureFinder project root.
        local = manifest.dirname.join(path)
        local.exist? ? local : @project_root.join(path)
      end

      raise ResolutionError, "#{role} in #{manifest} points to missing AMC: #{path}" unless path.file?
      Resolution.new(path: path.realpath, source: manifest.realpath.to_s, role: role)
    rescue Psych::Exception => e
      raise ResolutionError, "Could not parse state manifest #{manifest}: #{e.message}"
    end

    def load_authority_config
      return {} unless @authority_config.file?
      YAML.safe_load(@authority_config.read, permitted_classes: [], aliases: false) || {}
    rescue Psych::Exception => e
      raise ConfigurationError, "Could not parse authority config #{@authority_config}: #{e.message}"
    end

    def expand_project_path(path)
      pn = Pathname.new(path)
      pn.absolute? ? pn : @project_root.join(pn)
    end

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
