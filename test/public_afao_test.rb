# frozen_string_literal: true

require_relative "test_helper"

# Checks public selection refusals with content-free inputs and real validators.
# Exact public-document positives run separately with the pinned external input.
class PublicAfaoTest < Minitest::Test
  # Creates disposable output and historical authority; no public bytes are invented.
  def setup
    @temporary = File.realpath(Dir.mktmpdir("frontier-public-afao-"))
    @historical = TestPaths.write_afao(@temporary, version: "1.7")
    @public = File.join(@temporary, AfFrontier::AnalysisOntologyResolver::PUBLIC_AFAO.fetch("path"))
    @output = File.join(@temporary, "pack")
    @registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
  end

  # Removes only this test's disposable files; filesystem errors propagate.
  def teardown
    FileUtils.remove_entry(@temporary)
  end

  # The configured locator selects the exact public basename and reviewed identity.
  def test_default_selects_the_reviewed_public_contract
    binding = AfFrontier::AnalysisOntologyResolver::PUBLIC_AFAO
    assert_equal "394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf", binding.fetch("revision")
    assert_equal "dcfad224ab9517272504a508f935a804032d04a7c812ede10498921ce4585fa1", binding.fetch("sha256")
    assert_equal 339101, binding.fetch("bytes")
    config = YAML.safe_load_file(AfFrontier::Paths.repo_root.join("config/authority.yml"))
    assert_equal "public", config.dig("afao", "selection")
    assert_equal "af-specification-md/#{binding.fetch('path')}", config.dig("afao", "path")
    error = assert_raises(AfFrontier::ResolutionError) do
      AfFrontier::AnalysisOntologyResolver.new(project_root: @temporary).resolve
    end
    assert_includes error.message, "af-specification-md/#{binding.fetch('path')}"
  end

  # Real CLI refusals never replace CURRENT or existing generations/fixture inputs.
  def test_missing_wrong_version_and_changed_bytes_preserve_the_pack
    assert_cli_success("--afao", @historical)
    published = inventory(@output)
    protected = inventory(TestPaths::FIXTURES)
    [[nil, "does not exist"], ["## Version 1.7\n", "version mismatch"],
     ["## Version 1.6.1\n", "content mismatch"],
     ["## Version 1.6.1\n".ljust(339101), "content mismatch"]].each do |bytes, message|
      File.write(@public, bytes) unless bytes.nil?
      before_input = inventory(@temporary).reject { |path, _| path.start_with?(@output + "/") }
      code, error = invoke("--public-afao", @public)
      assert_equal 1, code, error
      assert_includes error, message
      assert_equal published, inventory(@output)
      assert_equal protected, inventory(TestPaths::FIXTURES)
      assert_equal before_input, inventory(@temporary).reject { |path, _| path.start_with?(@output + "/") }
    end
    assert_cli_success("--afao", @historical)
    assert_equal "1.7", AfFrontier::Pack.new(root: @output).manifest.dig("inputs", "afao", "version")
  end

  # A direct builder cannot rehash invalid public bytes into a selected public pack.
  def test_builder_enforces_public_identity_at_consumption
    File.write(@public, "## Version 1.6.1\n")
    error = assert_raises(AfFrontier::ResolutionError) do
      AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: @registry,
        afao_path: @public, public_afao: true, output_root: @output).build
    end
    assert_includes error.message, "content mismatch"
    refute_path_exists @output
  end

  # Contradictory selectors fail explicitly; neither one silently wins.
  def test_public_and_historical_selectors_are_mutually_exclusive
    code, error = invoke("--afao", @historical, "--public-afao", @public)
    assert_equal 1, code
    assert_includes error, "Select only one"
    refute_path_exists @output
  end

  # Public selection also refuses a historical basename or incompatible config.
  def test_public_filename_and_configured_version_are_checked
    error = assert_raises(AfFrontier::ResolutionError) do
      AfFrontier::AnalysisOntologyResolver.new.resolve(public_afao: @historical)
    end
    assert_includes error.message, "filename mismatch"
    authority = File.join(@temporary, "authority.yml")
    File.write(authority, YAML.dump({"afao" => {"selection" => "public", "path" => @public, "version" => "1.7"}}))
    error = assert_raises(AfFrontier::ResolutionError) do
      AfFrontier::AnalysisOntologyResolver.new(authority_config: authority).resolve
    end
    assert_includes error.message, "Configured public AFAO version"
  end

  private

  # Runs the supported CLI with frozen AMC and safe corpus; returns status/error.
  def invoke(*selectors)
    error = StringIO.new
    arguments = ["build", "--amc", TestPaths::AMC, "--source-registry", TestPaths::REGISTRY,
      "--corpus-root", TestPaths::CORPUS, "--output", @output, *selectors]
    [AfFrontier::CLI.new(arguments, out: StringIO.new, err: error).run, error.string]
  end

  # Asserts successful historical selection with diagnostics on failure.
  def assert_cli_success(*selectors)
    code, error = invoke(*selectors)
    assert_equal 0, code, error
  end

  # Binds every file's digest/mode to detect writes to protected inputs/output.
  def inventory(root)
    Dir.glob(File.join(root, "**/*")).select { |path| File.file?(path) }.sort.to_h do |path|
      [path, [Digest::SHA256.file(path).hexdigest, File.stat(path).mode & 0o777]]
    end
  end
end
