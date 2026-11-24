# frozen_string_literal: true

require "optparse"
require "json"
require "yaml"
require "pathname"

module AfFrontier
  class CLI
    def initialize(argv, out: $stdout, err: $stderr, input: $stdin)
      @argv = argv.dup
      @out = out
      @err = err
      @input = input
    end

    def run
      command = @argv.shift
      case command
      when "build" then build
      when "doctor" then doctor
      when "show" then show
      when "select" then select_cmd
      when "source" then source_cmd
      when "bundle" then bundle
      when "help", nil then help
      when "version", "--version", "-v" then @out.puts(VERSION); 0
      else
        raise ConfigurationError, "Unknown command #{command.inspect}. Run 'bin/af-frontier help'."
      end
    rescue AfFrontier::Error, OptionParser::ParseError => e
      @err.puts("ERROR: #{e.message}")
      1
    end

    private

    # Builds from selected authorities after parsing all overrides. Returns zero
    # on success; missing configuration/invalid operands raise AfFrontier errors.
    def build
      opts = {}
      parser = OptionParser.new do |o|
        o.banner = "Usage: bin/af-frontier build [options]"
        o.on("--amc PATH") { |v| opts[:amc] = v }
        o.on("--state PATH") { |v| opts[:state] = v }
        o.on("--source-registry PATH") { |v| opts[:source_registry] = v }
        o.on("--reviewed-source PATH") { |v| opts[:reviewed_source] = v }
        o.on("--corpus-root PATH") { |v| opts[:corpus_root] = v }
        o.on("--afao PATH") { |v| opts[:afao] = v }
        o.on("--public-afao PATH") { |v| opts[:public_afao] = v }
        o.on("--output PATH") { |v| opts[:output] = v }
      end
      parser.parse!(@argv)
      opts.each do |name, value|
        if value.to_s.strip.empty?
          raise ConfigurationError, "--#{name.to_s.tr('_', '-')} requires a nonblank path"
        end
      end

      opts[:output] ||= Paths.output_root.to_s

      resolution = CanonicalHeadResolver.new.resolve(explicit_amc: opts[:amc], state_path: opts[:state])
      @out.puts(resolution.role == "explicit" ? "Using explicit AMC (frozen artifact; not accepted-state resolution):" : "No --amc supplied. Resolved canonical catalog head:")
      @out.puts("  #{resolution.path}")
      @out.puts("  version: #{resolution.version}") if resolution.version
      @out.puts("  sha256: #{resolution.sha256}") if resolution.sha256
      @out.puts("Authority: #{resolution.source}")
      @out.puts

      afao_resolution = AnalysisOntologyResolver.new.resolve(explicit_afao: opts[:afao], public_afao: opts[:public_afao])
      @out.puts(opts[:afao] || opts[:public_afao] ? "Using explicit AFAO:" : "Resolved AFAO authority:")
      @out.puts("  #{afao_resolution.path}")
      @out.puts("  version: #{afao_resolution.version}")
      @out.puts("  sha256: #{afao_resolution.sha256}")
      @out.puts("Authority: #{afao_resolution.source}")
      if afao_resolution.public_specification
        @out.puts("Public specification revision: #{afao_resolution.public_specification.fetch('revision')}")
      end
      @out.puts

      opts[:corpus_root] ||= Paths.project_root.join("af-source-md-data").to_s
      opts[:source_registry] ||= File.join(opts[:corpus_root], "source_registry.yml")
      unless File.file?(opts[:source_registry])
        raise ConfigurationError, "Source registry not found. Supply --source-registry PATH (default tried: #{opts[:source_registry]})"
      end

      registry = SourceRegistry.new(path: opts[:source_registry], corpus_root: opts[:corpus_root])
      manifest = PackBuilder.new(
        amc_path: resolution.path,
        source_registry: registry,
        reviewed_source_path: opts[:reviewed_source],
        afao_path: afao_resolution.path,
        public_afao: !afao_resolution.public_specification.nil?,
        output_root: opts[:output]
      ).build

      @out.puts(
        "Built #{manifest.dig('counts', 'adventures')} adventures across #{manifest.dig('counts', 'sources')} sources " \
        "(#{manifest.dig('counts', 'source_resolved')} source-resolved; #{manifest.dig('counts', 'source_unresolved')} unresolved)."
      )
      @out.puts("Frontier pack written:")
      @out.puts("  #{Pathname.new(opts[:output]).expand_path}")
      0
    end

    def doctor
      opts = { root: Paths.output_root.to_s }
      OptionParser.new do |o|
        o.banner = "Usage: bin/af-frontier doctor [--root PATH]"
        o.on("--root PATH") { |v| opts[:root] = v }
      end.parse!(@argv)
      pack = Pack.new(root: opts[:root])
      announce(pack)
      Doctor.new(pack: pack).check
      @out.puts("OK: frontier pack integrity checks passed")
      0
    end

    def show
      id = @argv.shift or raise ConfigurationError, "Usage: bin/af-frontier show ADV-XXXX [--format json|markdown]"
      opts = { format: "markdown" }
      OptionParser.new { |o| o.on("--format FORMAT") { |v| opts[:format] = v } }.parse!(@argv)
      pack = Pack.new
      announce(pack)
      record = pack.fetch(id)
      if opts[:format] == "json"
        @out.puts(JSON.pretty_generate(record))
      else
        @out.puts("# #{record['adventure_id']} — #{record['title']}")
        @out.puts
        @out.puts("```json")
        @out.puts(JSON.pretty_generate(record))
        @out.puts("```")
      end
      0
    end

    def select_cmd
      opts = { where: [], ids_only: false }
      OptionParser.new do |o|
        o.banner = "Usage: bin/af-frontier select --where 'GMPB<=2' [--where 'CPA>=4'] [--ids-only]"
        o.on("--where EXPR") { |v| opts[:where] << v }
        o.on("--ids-only") { opts[:ids_only] = true }
      end.parse!(@argv)
      raise ConfigurationError, "select requires at least one --where expression" if opts[:where].empty?
      pack = Pack.new
      announce(pack)
      rows = Selector.new(pack: pack).select(opts[:where])
      if opts[:ids_only]
        rows.each { |row| @out.puts(row["adventure_id"]) }
      else
        rows.each { |row| @out.puts("#{row['adventure_id']}\t#{row['title']}") }
        @err.puts("Matched #{rows.length} adventures.")
      end
      0
    end

    def source_cmd
      id = @argv.shift or raise ConfigurationError, "Usage: bin/af-frontier source ADV-XXXX [--emit]"
      opts = { emit: false }
      OptionParser.new { |o| o.on("--emit") { opts[:emit] = true } }.parse!(@argv)
      pack = Pack.new
      announce(pack)
      resolver = SourceResolver.new(pack: pack)
      if opts[:emit]
        @out.write(resolver.emit(id))
      else
        @out.puts(JSON.pretty_generate(resolver.locator(id)))
      end
      0
    end

    def bundle
      opts = { format: "markdown", with_source: false }
      OptionParser.new do |o|
        o.banner = "Usage: bin/af-frontier bundle --ids ADV-0001,ADV-0002|-' [options]"
        o.on("--ids IDS") { |v| opts[:ids] = v }
        o.on("--with-source") { opts[:with_source] = true }
        o.on("--format FORMAT") { |v| opts[:format] = v }
        o.on("--output PATH") { |v| opts[:output] = v }
      end.parse!(@argv)
      raise ConfigurationError, "bundle requires --ids LIST or --ids -" unless opts[:ids]

      ids = if opts[:ids] == "-"
        @input.read.lines.map(&:strip).reject(&:empty?)
      else
        opts[:ids].split(",").map(&:strip)
      end

      pack = Pack.new
      announce(pack)
      path = Bundler.new(pack: pack).write(ids: ids, format: opts[:format], with_source: opts[:with_source], path: opts[:output])
      @out.puts("Bundled #{ids.uniq.length} adventures.")
      @out.puts
      @out.puts("Bundle written:")
      @out.puts("  #{path}")
      0
    end

    def help
      @out.puts <<~TEXT
        af-frontier #{VERSION}

        Usage:
          bin/af-frontier build [options]
          bin/af-frontier doctor
          bin/af-frontier show ADV-XXXX [--format json|markdown]
          bin/af-frontier select --where 'GMPB<=2' [--where 'CPA>=4'] [--ids-only]
          bin/af-frontier source ADV-XXXX [--emit]
          bin/af-frontier bundle --ids ADV-0001,ADV-0002|-' [--with-source] [--format markdown|json]

        Build inputs:
          --state PATH (catalog_head), or --amc PATH / AF_FRONTIER_AMC (frozen artifact)
          --public-afao PATH (pinned public identity), or --afao PATH (historical explicit input)
          --source-registry PATH --corpus-root PATH --output PATH
          --reviewed-source PATH (private declaration for one two-volume catalog entry)
          AF_PROJECT_ROOT is required only for omitted relative authority/corpus defaults.
          No project root is discovered. Pack reads need only AF_FRONTIER_OUTPUT.

        Generated output lives under:
          #{Paths.output_root}
      TEXT
      0
    end

    def announce(pack)
      @err.puts("Frontier pack: #{pack.authority_label}")
    end

  end
end
