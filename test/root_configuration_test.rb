# frozen_string_literal: true

require_relative "test_helper"

# Exercises library selection using only the existing mechanical fixtures.
class RootConfigurationTest < Minitest::Test
  # Creates isolated authorities/output and saves caller selectors for restoration.
  def setup
    @environment = ENV.to_h.slice("AF_PROJECT_ROOT", "AF_FRONTIER_AMC", "AF_FRONTIER_OUTPUT")
    %w[AF_PROJECT_ROOT AF_FRONTIER_AMC AF_FRONTIER_OUTPUT].each { |key| ENV.delete(key) }
    # Match the realpaths recorded by authority and source resolvers.
    @temporary = File.realpath(Dir.mktmpdir("frontier-roots-"))
    @library = create_library("first")
    @output = File.join(@temporary, "pack")
    ENV["AF_FRONTIER_OUTPUT"] = @output
  end

  # Restores environment and removes only this test's disposable directory.
  def teardown
    %w[AF_PROJECT_ROOT AF_FRONTIER_AMC AF_FRONTIER_OUTPUT].each { |key| ENV.delete(key) }
    ENV.update(@environment)
    FileUtils.remove_entry(@temporary)
  end

  # Fully selected builds and API resolutions never consult an unused root.
  def test_explicit_inputs_do_not_consult_project_root
    AfFrontier::Paths.stub(:project_root, ->(*) { flunk "unused project root consulted" }) do
      assert_success(*build_arguments)
      assert_equal "catalog_head", AfFrontier::CanonicalHeadResolver.new.resolve(state_path: state).role
      assert_equal "explicit", AfFrontier::CanonicalHeadResolver.new.resolve(explicit_amc: catalog).role
      assert_equal "--afao", AfFrontier::AnalysisOntologyResolver.new.resolve(explicit_afao: ontology).source
    end
    ["", "  ", File.join(@temporary, "absent"), catalog].each do |unused_root|
      ENV["AF_PROJECT_ROOT"] = unused_root
      assert_success(*build_arguments)
    end
  end

  # A configured root retains relative catalog/corpus defaults with historical AFAO.
  def test_configured_layout_and_relative_explicit_operands
    ENV["AF_PROJECT_ROOT"] = @library
    assert_success("build", "--afao", ontology)
    assert_equal catalog, current_pack.manifest.dig("inputs", "amc", "path")
    ENV.delete("AF_PROJECT_ROOT")
    Dir.chdir(@library) do
      arguments = build_arguments.map { |value| value.delete_prefix(@library + "/") }
      assert_success(*arguments)
    end
    assert_equal catalog, current_pack.manifest.dig("inputs", "amc", "path")
  end

  # Missing defaults require configuration only when selected; blank roots never mean cwd.
  def test_missing_and_invalid_needed_roots
    [nil, "", "  ", File.join(@temporary, "absent"), catalog].each do |root|
      root.nil? ? ENV.delete("AF_PROJECT_ROOT") : ENV["AF_PROJECT_ROOT"] = root
      %w[--state --afao --corpus-root].each do |option|
        arguments = build_arguments
        arguments.slice!(arguments.index(option), 2)
        code, _output, error = invoke(*arguments)
        assert_equal 1, code
        assert_includes error, "AF_PROJECT_ROOT"
      end
    end
    arguments = build_arguments
    arguments.slice!(arguments.index("--source-registry"), 2)
    assert_success(*arguments)
  end

  # Supported frozen-artifact overrides win even over invalid lower-priority selectors.
  def test_artifact_and_output_precedence
    ENV["AF_FRONTIER_AMC"] = File.join(@temporary, "missing.xlsx")
    assert_success(*build_arguments, "--amc", catalog, "--state", "missing-state")
    ENV["AF_FRONTIER_AMC"] = catalog
    _code, output, _error = assert_success(*build_arguments, "--state", "missing-state")
    assert_includes output, "explicit AMC"
    refute_includes output, "Resolved canonical catalog head"
    ENV["AF_FRONTIER_OUTPUT"] = File.join(@temporary, "unselected-output")
    assert_success(*build_arguments, "--output", @output)
    refute_path_exists ENV["AF_FRONTIER_OUTPUT"]
  end

  # Invalid explicit operands refuse without defaults, publication or authority writes.
  def test_invalid_operands_preserve_published_pack_and_authorities
    assert_success(*build_arguments)
    before_output = inventory(@output)
    before_library = inventory(@library)
    ENV["AF_PROJECT_ROOT"] = @library
    %w[--state --afao --source-registry --corpus-root --amc --output].each do |option|
      values = option == "--output" ? ["", "  "] : ["", "  ", File.join(@temporary, "missing")]
      values.each do |value|
        code, _output, error = invoke(*build_arguments, option, value)
        assert_equal 1, code, "#{option} #{value.inspect}: #{error}"
        assert_match(/ERROR:/, error)
        assert_equal before_output, inventory(@output)
        assert_equal before_library, inventory(@library)
      end
    end
    assert_success(*build_arguments)
  end

  # Alternating libraries retains real locators; identical selections repeat exact payloads.
  def test_two_libraries_and_repeatable_payloads
    assert_success(*build_arguments)
    first_payload = payload
    first_inventory = inventory(@output)
    second = create_library("second")
    second_output = File.join(@temporary, "second-pack")
    assert_success(*build_arguments(second), "--output", second_output)
    other_pack = AfFrontier::Pack.new(root: second_output)
    assert_equal File.join(second, "af-xlsx-data-sources", File.basename(TestPaths::AMC)),
                 other_pack.manifest.dig("inputs", "amc", "path")
    other_pack.adventures.each do |record|
      assert record.dig("source_locator", "path").start_with?(second + "/")
    end
    refute_equal first_payload, payload(second_output)
    assert_equal first_inventory, inventory(@output)
    assert_success(*build_arguments)
    assert_equal first_payload, payload
    assert_nil current_pack.fetch("ADV-0002").dig("assessments", "FW")
  end

  # Pack reads, source emission and deliberate bundles remain independent of build roots.
  def test_pack_commands_and_help_never_consult_project_root
    assert_success(*build_arguments)
    AfFrontier::Paths.stub(:project_root, ->(*) { flunk "pack read consulted project root" }) do
      [["help"], ["version"], ["doctor"], ["show", "ADV-0001"],
       ["select", "--where", "GMPB<=2"], ["source", "ADV-0001", "--emit"]].each do |arguments|
        assert_success(*arguments)
      end
      bundle_path = File.join(@temporary, "bundle.json")
      arguments = ["bundle", "--ids", "ADV-0001", "--format", "json", "--output", bundle_path]
      assert_success(*arguments)
      refute JSON.parse(File.read(bundle_path)).fetch("adventures").first.key?("source_evidence")
      assert_success(*arguments, "--with-source")
      assert JSON.parse(File.read(bundle_path)).fetch("adventures").first.key?("source_evidence")
    end
  end

  # Absolute configured authorities need no project root, including later unused defaults.
  def test_absolute_authority_configuration
    authority = File.join(@temporary, "authority.yml")
    File.write(authority, YAML.dump({"state_manifests" => [state, "unused/PROJECT_STATE.yml"],
      "afao" => {"path" => ontology, "version" => "1.6.1"}}))
    assert_equal "catalog_head", AfFrontier::CanonicalHeadResolver.new(authority_config: authority).resolve.role
    assert_equal ontology, AfFrontier::AnalysisOntologyResolver.new(authority_config: authority).resolve.path.to_s
  end

  private

  # Copies safe fixture bytes into a conventional selected layout; returns its root.
  def create_library(name)
    root = File.join(@temporary, name)
    catalog_root = File.join(root, "af-xlsx-data-sources")
    corpus = File.join(root, "af-source-md-data")
    specification = File.join(root, "md-specification-files")
    FileUtils.mkdir_p([catalog_root, specification])
    FileUtils.cp(TestPaths::AMC, catalog_root)
    FileUtils.cp_r(TestPaths::CORPUS, corpus)
    FileUtils.cp(TestPaths::REGISTRY, File.join(corpus, "source_registry.yml"))
    TestPaths.write_afao(specification)
    entry = {"version" => "9.9.9", "filename" => File.basename(TestPaths::AMC),
      "sha256" => Digest::SHA256.file(TestPaths::AMC).hexdigest, "bytes" => File.size(TestPaths::AMC)}
    manifest = {"schema_version" => AfFrontier::CanonicalHeadResolver::PROJECT_STATE_SCHEMA}
    AfFrontier::CanonicalHeadResolver::PROJECT_STATE_ROLES.each { |role| manifest[role] = entry.dup }
    File.write(File.join(catalog_root, "PROJECT_STATE.yml"), YAML.dump(manifest))
    root
  end

  # Returns explicit CLI build arguments for a selected mechanical library.
  def build_arguments(root = @library)
    ["build", "--state", state(root), "--afao", ontology(root),
     "--source-registry", File.join(root, "af-source-md-data/source_registry.yml"),
     "--corpus-root", File.join(root, "af-source-md-data"), "--output", @output]
  end

  # Returns the selected state locator without reading it.
  def state(root = @library)
    File.join(root, "af-xlsx-data-sources/PROJECT_STATE.yml")
  end

  # Returns the selected catalog locator without reading it.
  def catalog
    File.join(@library, "af-xlsx-data-sources", File.basename(TestPaths::AMC))
  end

  # Returns the selected fixture ontology locator without reading it.
  def ontology(root = @library)
    File.join(root, "md-specification-files/AdventureFinder_Analysis_Ontology_v1.6.1.md")
  end

  # Runs the real CLI implementation with captured streams; returns status/out/err.
  def invoke(*arguments)
    output = StringIO.new
    error = StringIO.new
    [AfFrontier::CLI.new(arguments, out: output, err: error).run, output.string, error.string]
  end

  # Asserts CLI success and returns its streams; failures include diagnostics.
  def assert_success(*arguments)
    result = invoke(*arguments)
    assert_equal 0, result.first, result.last
    result
  end

  # Returns the verified pack; integrity failures propagate to the test.
  def current_pack(root = @output)
    AfFrontier::Pack.new(root: root)
  end

  # Returns unmodified deterministic generation bytes, excluding unique CURRENT.
  def payload(root = @output)
    generation = current_pack(root).artifact_root
    %w[manifest.json adventures.jsonl sources.jsonl].to_h { |name| [name, File.binread(File.join(generation, name))] }
  end

  # Returns file hashes/modes to detect authority or prior-generation mutations.
  def inventory(root)
    Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).sort.select { |path| File.file?(path) }.to_h do |path|
      [path, [Digest::SHA256.file(path).hexdigest, File.stat(path).mode & 0o777]]
    end
  end
end
