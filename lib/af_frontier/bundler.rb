# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"

module AfFrontier
  class Bundler
    def initialize(pack: Pack.new, source_resolver: nil)
      @pack = pack
      @source_resolver = source_resolver || SourceResolver.new(pack: pack)
    end

    def write(ids:, format: "markdown", with_source: false, path: nil)
      ids = ids.map(&:strip).reject(&:empty?).uniq
      raise ConfigurationError, "bundle requires at least one Adventure ID" if ids.empty?
      adventures = ids.map { |id| @pack.fetch(id) }

      ext = format == "json" ? "json" : "md"
      path ||= default_path(ids, ext)
      path = Pathname.new(path).expand_path
      FileUtils.mkdir_p(path.dirname)

      body = if format == "json"
        json_bundle(adventures, with_source)
      elsif format == "markdown"
        markdown_bundle(adventures, with_source)
      else
        raise ConfigurationError, "Unsupported bundle format #{format.inspect}; use markdown or json"
      end

      File.write(path, body)
      path.realpath
    end

    private

    def default_path(ids, ext)
      FileUtils.mkdir_p(Paths.bundles_root)
      label = if ids.length <= 4
        ids.join("_")
      else
        "bundle-#{ids.length}-adventures"
      end
      Paths.bundles_root.join("#{label}.#{ext}")
    end

    def markdown_bundle(adventures, with_source)
      out = +"# AdventureFinder Frontier Context\n\n"
      out << "Frontier pack: #{@pack.authority_label}\n\n"
      adventures.each do |adv|
        out << "## #{adv['adventure_id']} — #{adv['title']}\n\n"
        out << "### Structured record\n\n```json\n#{JSON.pretty_generate(adv)}\n```\n\n"
        if with_source
          out << "### Canonical source evidence\n\n"
          out << @source_resolver.emit(adv["adventure_id"])
          out << "\n"
        end
      end
      out
    end

    def json_bundle(adventures, with_source)
      payload = {
        "frontier_pack" => @pack.authority_label,
        "adventures" => adventures.map do |adv|
          row = { "record" => adv }
          row["source_evidence"] = @source_resolver.emit(adv["adventure_id"]) if with_source
          row
        end
      }
      JSON.pretty_generate(payload) + "\n"
    end
  end
end
