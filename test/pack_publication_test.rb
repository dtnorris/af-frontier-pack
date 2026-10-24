# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require "timeout"

# Exercises publication boundaries using synthetic catalog rows and real files.
class PackPublicationTest < Minitest::Test
  # Prepares disposable authorities and rows; filesystem/parser errors fail setup.
  def setup
    @dir = Dir.mktmpdir("pack-publication-")
    @afao = File.join(@dir, "AdventureFinder_Analysis_Ontology_v1.6.1.md")
    File.write(@afao, "# Ontology\n## Version 1.6.1\n")
    @registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
    @rows = AfFrontier::XlsxCatalogReader.new(TestPaths::AMC).rows
    @replacement = @rows.first(1).map { |row| row.merge("Adventure Title" => "NEW GENERATION") }
    @root = File.join(@dir, "pack")
  end

  # Removes only this test's disposable root; returns FileUtils' removal result.
  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Proves before/after faults at each write and rename expose only complete packs.
  def test_fault_matrix_for_first_build_and_rebuild
    %w[adventures.jsonl sources.jsonl manifest.json generation pointer CURRENT].product(
      %i[before after], [false, true]
    ).each_with_index do |(boundary, side, rebuilding), index|
      @root = File.join(@dir, "matrix-#{index}")
      build if rebuilding
      previous = AfFrontier::Pack.new(root: @root) if rebuilding
      old_pointer = File.binread(File.join(@root, "CURRENT")) if rebuilding
      failure = assert_raises(IOError) do
        at_boundary(boundary, side, -> { raise IOError, "injected #{side} #{boundary}" }) do
          build(@replacement)
        end
      end
      assert_includes failure.message, "injected"
      committed = boundary == "CURRENT" && side == :after
      if committed
        assert_snapshot(AfFrontier::Pack.new(root: @root), 1, "NEW GENERATION")
      elsif rebuilding
        assert_equal old_pointer, File.binread(File.join(@root, "CURRENT"))
        assert_snapshot(AfFrontier::Pack.new(root: @root), 3, @rows.first["Adventure Title"])
      else
        assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
        refute File.exist?(File.join(@root, "CURRENT"))
      end
      assert_snapshot(previous, 3, @rows.first["Adventure Title"]) if previous
      assert_empty Dir.glob(File.join(@root, "generations", ".building-*"))
    end
  end

  # Coordinates writer and delayed readers with queues, never timing-only sleeps.
  def test_readers_remain_bound_across_a_concurrent_rebuild
    build
    delayed = AfFrontier::Pack.new(root: @root)
    memoized = AfFrontier::Pack.new(root: @root)
    memoized.manifest
    memoized.adventures
    ready = Queue.new
    resume = Queue.new
    writer = nil
    at_boundary("adventures.jsonl", :after, lambda { ready << true; resume.pop }) do
      writer = Thread.new { build(@replacement) }
      Timeout.timeout(5) { ready.pop }
      during = AfFrontier::Pack.new(root: @root)
      assert_snapshot(during, 3, @rows.first["Adventure Title"])
      resume << true
      Timeout.timeout(5) { writer.value }
      [delayed, memoized, during].each do |reader|
        assert_snapshot(reader, 3, @rows.first["Adventure Title"])
      end
      assert_snapshot(AfFrontier::Pack.new(root: @root), 1, "NEW GENERATION")
    end
  ensure
    resume << true if resume
    writer.join if writer
  end

  # A writer paused at commit cannot lose its files when another writer publishes.
  def test_concurrent_writers_keep_each_others_generations
    build
    ready = Queue.new
    resume = Queue.new
    writer = nil
    action = lambda do
      if Thread.current == writer
        ready << true
        resume.pop
      end
    end
    reader = ->(*) { Struct.new(:rows).new(Thread.current == writer ? @replacement : @rows) }
    AfFrontier::XlsxCatalogReader.stub(:new, reader) do
      at_boundary("CURRENT", :before, action) do
        # Set the thread identity before allowing it to reach the publication hook.
        start = Queue.new
        writer = Thread.new { start.pop; builder.build }
        start << true
        Timeout.timeout(5) { ready.pop }
        builder.build
        other = AfFrontier::Pack.new(root: @root)
        resume << true
        Timeout.timeout(5) { writer.value }
        assert_snapshot(other, 3, @rows.first["Adventure Title"])
        assert_snapshot(AfFrontier::Pack.new(root: @root), 1, "NEW GENERATION")
        assert_equal 3, Dir.glob(File.join(@root, "generations", "generation-*")).length
      end
    end
  ensure
    resume << true if resume
    writer.join if writer
  end

  # Abruptly exits only owned fixture children, including after the commit point.
  def test_process_interruption_never_exposes_a_partial_generation
    %w[adventures.jsonl CURRENT].product([false, true]).each_with_index do |(boundary, rebuilding), index|
      @root = File.join(@dir, "crash-#{index}")
      build if rebuilding
      old = AfFrontier::Pack.new(root: @root) if rebuilding
      child = fork do
        at_boundary(boundary, :after, -> { Process.exit!(73) }) { build(@replacement) }
      end
      _, status = Process.waitpid2(child)
      assert_equal 73, status.exitstatus
      if boundary == "CURRENT"
        assert_snapshot(AfFrontier::Pack.new(root: @root), 1, "NEW GENERATION")
      elsif rebuilding
        assert_snapshot(AfFrontier::Pack.new(root: @root), 3, @rows.first["Adventure Title"])
      else
        assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
      end
      assert_snapshot(old, 3, @rows.first["Adventure Title"]) if old
    end
  end

  # Missing authority, duplicate IDs and invalid assessments fail before publication.
  def test_invalid_inputs_preserve_previous_pack_and_first_build_fails_closed
    [false, true].each do |rebuilding|
      @root = File.join(@dir, "invalid-#{rebuilding}")
      build if rebuilding
      pointer = File.binread(File.join(@root, "CURRENT")) if rebuilding
      invalid_rows = [@rows + [@rows.first], [@rows.first.merge("Combat Emphasis" => 9)]]
      invalid_rows.each { |rows| assert_raises(AfFrontier::IntegrityError) { build(rows) } }
      File.rename(@afao, "#{@afao}.missing")
      assert_raises(AfFrontier::ConfigurationError) { build }
      File.rename("#{@afao}.missing", @afao)
      File.write(@afao, "invalid ontology without version heading")
      assert_raises(AfFrontier::ResolutionError) { build }
      File.write(@afao, "# Ontology\n## Version 1.6.1\n")
      invalid_amc = File.join(@dir, "invalid.xlsx")
      File.write(invalid_amc, "not a workbook")
      assert_raises(AfFrontier::IntegrityError) do
        AfFrontier::PackBuilder.new(amc_path: invalid_amc, source_registry: @registry,
                                    afao_path: @afao, output_root: @root).build
      end
      if rebuilding
        assert_equal pointer, File.binread(File.join(@root, "CURRENT"))
        assert_snapshot(AfFrontier::Pack.new(root: @root), 3, @rows.first["Adventure Title"])
      else
        assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
        refute Dir.exist?(@root)
      end
    end
  end

  # Exercises the public CLI in real offline child processes and checks refusal
  # before any show output when even the otherwise-unused sources file is corrupt.
  def test_cli_build_show_and_corrupt_pack_refusal
    command = [RbConfig.ruby, File.expand_path("../bin/af-frontier", __dir__)]
    environment = { "AF_FRONTIER_OUTPUT" => @root }
    output, error, status = Open3.capture3(environment, *command, "build", "--amc", TestPaths::AMC,
      "--source-registry", TestPaths::REGISTRY, "--corpus-root", TestPaths::CORPUS, "--afao", @afao)
    assert status.success?, error
    assert_includes output, "Built 3 adventures across 2 sources"
    output, error, status = Open3.capture3(environment, *command, "show", "ADV-0001", "--format", "json")
    assert status.success?, error
    assert_equal "ADV-0001", JSON.parse(output)["adventure_id"]
    generation = AfFrontier::Pack.new(root: @root).artifact_root
    File.write(File.join(generation, "sources.jsonl"), "corrupt")
    output, error, status = Open3.capture3(environment, *command, "show", "ADV-0001", "--format", "json")
    assert_equal 1, status.exitstatus
    assert_empty output
    assert_includes error, "Artifact hash mismatch"
  end

  # Refuses every missing/corrupt artifact and malformed pointer/manifest shape.
  def test_artifacts_fail_closed_without_falling_back_to_legacy_files
    build
    original_pointer = File.binread(File.join(@root, "CURRENT"))
    generation = AfFrontier::Pack.new(root: @root).artifact_root
    # Legacy-looking files must never serve as fallback.
    %w[manifest.json adventures.jsonl sources.jsonl].each do |name|
      path = File.join(generation, name)
      original = File.binread(path)
      File.write(File.join(@root, name), original)
      File.unlink(path)
      assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
      File.binwrite(path, original + "corrupt")
      assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
      File.binwrite(path, original)
    end
    ["{", "[]", '{"generation":"../escape"}',
     JSON.generate("generation" => "generation-missing", "manifest_sha256" => "0" * 64)].each do |pointer|
      File.write(File.join(@root, "CURRENT"), pointer)
      assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
    end
    File.binwrite(File.join(@root, "CURRENT"), original_pointer)
    manifest_path = File.join(generation, "manifest.json")
    original_manifest = File.binread(manifest_path)
    [[], {}, JSON.parse(original_manifest).merge("counts" => {}),
     JSON.parse(original_manifest).merge("artifacts" => {}),
     JSON.parse(original_manifest).merge("artifacts" => { "adventures.jsonl" => { "sha256" => "bad" } })].each do |manifest|
      replace_manifest(generation, manifest)
      assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
    end
    File.binwrite(manifest_path, original_manifest)
    File.binwrite(File.join(@root, "CURRENT"), original_pointer)
    assert_snapshot(AfFrontier::Pack.new(root: @root), 3, @rows.first["Adventure Title"])
  end

  # Even with matching hashes, invalid JSONL and non-object records refuse use.
  def test_invalid_jsonl_with_matching_hash_is_refused
    build
    generation = AfFrontier::Pack.new(root: @root).artifact_root
    ["{broken\n", "[]\n"].each do |content|
      File.write(File.join(generation, "adventures.jsonl"), content)
      manifest = JSON.parse(File.read(File.join(generation, "manifest.json")))
      manifest["artifacts"]["adventures.jsonl"]["sha256"] = Digest::SHA256.hexdigest(content)
      replace_manifest(generation, manifest)
      assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
    end
  end

  # Legacy roots require rebuild; successful migration leaves old files untouched.
  def test_legacy_migration_is_explicit_and_does_not_mix_artifacts
    FileUtils.mkdir_p(@root)
    %w[manifest.json adventures.jsonl sources.jsonl].each { |name| File.write(File.join(@root, name), "legacy") }
    error = assert_raises(AfFrontier::IntegrityError) { AfFrontier::Pack.new(root: @root) }
    assert_includes error.message, "rebuild"
    build
    assert_snapshot(AfFrontier::Pack.new(root: @root), 3, @rows.first["Adventure Title"])
    %w[manifest.json adventures.jsonl sources.jsonl].each do |name|
      assert_equal "legacy", File.read(File.join(@root, name))
    end
    ENV.stub(:fetch, ->(name, default) { name == "AF_FRONTIER_OUTPUT" ? @root : default }) do
      assert_equal File.join(AfFrontier::Pack.new(root: @root).artifact_root, "manifest.json"), AfFrontier::Paths.manifest_path.to_s
    end
  end

  # Original-baseline normalized byte hashes preserve complete record semantics.
  def test_golden_content_and_repeat_builds_are_deterministic
    manifest = builder.build
    first = AfFrontier::Pack.new(root: @root)
    expected = {
      "adventures.jsonl" => "527f80c142d3924b7e2318c84da5f035d32e66881903d893bbfb306a644223a1",
      "sources.jsonl" => "6432f8a54882677d2223d2ce3fe8ba673df24c2ddc1a6fca670e6940d03bc1af",
      "manifest.json" => "675346919d0702f937d49cf9ef4ca2af34e2b0b193dc0da76b13be402ead15ff"
    }
    expected.each do |name, sha|
      bytes = if name == "manifest.json"
        JSON.pretty_generate(manifest.reject { |key, _| key == "artifacts" }) + "\n"
      else
        File.binread(File.join(first.artifact_root, name))
      end
      normalized = bytes.gsub(TestPaths::FIXTURES, "<FIXTURES>").gsub(@afao, "<AFAO>")
      assert_equal sha, Digest::SHA256.hexdigest(normalized), name
    end
    assert_equal manifest, builder.build
    second = AfFrontier::Pack.new(root: @root)
    expected.each_key do |name|
      assert_equal File.binread(File.join(first.artifact_root, name)), File.binread(File.join(second.artifact_root, name))
    end
    assert_equal %w[ADV-0001 ADV-0002 ADV-0003], second.adventures.map { |record| record["adventure_id"] }
    assert_equal first.sources, second.sources
    assert_equal AfFrontier::SourceResolver.new(pack: first).emit("ADV-0002"),
                 AfFrontier::SourceResolver.new(pack: second).emit("ADV-0002")
  end

  private

  # Returns a builder using offline fixtures and this test's disposable output.
  def builder
    AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: @registry, afao_path: @afao, output_root: @root)
  end

  # Builds selected synthetic rows, returning the manifest; propagates build errors.
  def build(rows = @rows)
    AfFrontier::XlsxCatalogReader.stub(:new, Struct.new(:rows).new(rows)) { builder.build }
  end

  # Asserts all three reader views agree on the expected synthetic generation.
  def assert_snapshot(pack, count, title)
    assert_equal count, pack.manifest.dig("counts", "adventures")
    assert_equal count, pack.adventures.length
    assert_equal title, pack.adventures.first["title"]
    assert_equal pack.manifest.dig("counts", "sources"), pack.sources.length
    assert_equal pack.adventures.map { |row| row.dig("source", "source_id") }.uniq.sort,
                 pack.sources.map { |row| row["source_id"] }
  end

  # Replaces a synthetic manifest and its pointer hash to test structural errors.
  def replace_manifest(generation, manifest)
    content = JSON.generate(manifest)
    File.write(File.join(generation, "manifest.json"), content)
    pointer = JSON.parse(File.read(File.join(@root, "CURRENT")))
    pointer["manifest_sha256"] = Digest::SHA256.hexdigest(content)
    File.write(File.join(@root, "CURRENT"), JSON.generate(pointer))
  end

  # Executes action immediately before/after one real filesystem boundary while
  # yielding the test body. Errors propagate; stubs are always restored.
  def at_boundary(boundary, side, action, &body)
    operation = lambda do |name, &original|
      action.call if name == boundary && side == :before
      result = original.call
      action.call if name == boundary && side == :after
      result
    end
    jsonl_write = AfFrontier::Jsonl.method(:write)
    file_write = File.method(:write)
    rename = File.method(:rename)
    tempfile_create = Tempfile.method(:create)
    AfFrontier::Jsonl.stub(:write, ->(path, records) { operation.call(File.basename(path)) { jsonl_write.call(path, records) } }) do
      File.stub(:write, ->(path, content) { operation.call(File.basename(path)) { file_write.call(path, content) } }) do
        File.stub(:rename, lambda { |from, to|
          name = File.basename(to) == "CURRENT" ? "CURRENT" : "generation"
          operation.call(name) { rename.call(from, to) }
        }) do
          Tempfile.stub(:create, lambda { |*args, &block|
            tempfile_create.call(*args) do |file|
              write = file.method(:write)
              file.stub(:write, ->(content) { operation.call("pointer") { write.call(content) } }) { block.call(file) }
            end
          }, &body)
        end
      end
    end
  end
end
