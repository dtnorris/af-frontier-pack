# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Exercise the reviewed source build and readers through the public executable.
class ReviewedSourceCliTest < Minitest::Test
  FIXTURE = File.join(TestPaths::FIXTURES, "reviewed_source")
  FILES = %w[volume-one.md volume-two.md].freeze

  # Select a synthetic catalog and isolated corpus and output for each test.
  def setup
    @dir = Dir.mktmpdir
    @root = File.join(@dir, "pack")
    @current = File.join(@root, "CURRENT")
    @registry = File.join(@dir, "registry.yml")
    @declaration = File.join(@dir, "review.json")
    @afao = TestPaths.write_afao(@dir)
    FileUtils.cp(Dir.glob(File.join(FIXTURE, "*.{md,yml}")), @dir)
    FileUtils.cp(File.join(TestPaths::CORPUS, "Book_One_LLM_Edition.md"), @dir)
    @review = {
      "adventure_id" => "ADV-0004",
      "adventure_title" => "Example Campaign",
      "source_book" => "Book Two",
      "start_page" => 17,
      "end_page" => 25,
      "files" => FILES.to_h { |file| [file, Digest::SHA256.file(File.join(@dir, file)).hexdigest] }
    }
    File.write(@declaration, JSON.generate(@review))
  end

  # Remove the synthetic build inputs and generated pack.
  def teardown
    FileUtils.remove_entry(@dir)
  end

  # A reviewed row is discoverable, keeps its catalog values, and carries two
  # verified source references while its neighboring excerpts remain exact.
  def test_build_doctor_and_read_reviewed_pack
    assert_includes build, "Built 4 adventures across 2 sources"
    assert_includes cli_success("doctor"), "integrity checks passed"
    parent = JSON.parse(cli_success("show", "ADV-0004", "--format", "json"))
    assert_equal "Example Campaign", parent.fetch("title")
    assert_equal({
      "source_id" => "Book Two", "book" => "Book Two", "publisher" => "Example Press",
      "start_page" => 17, "end_page" => 25, "page_count" => 9
    }, parent.fetch("source"))
    assessments = parent.fetch("assessments")
    assert_equal({ "NoS" => 6, "LSLE" => { "start" => 1, "end" => 5 }, "CE" => 4, "RSMD" => 5 },
      assessments.reject { |_key, value| value.nil? })
    assert_nil parent["played"]
    assert_nil parent["parentage"]
    assert_equal "ADV-0004\n", cli_success("select", "--where", "NoS=6", "--ids-only")

    locator = JSON.parse(cli_success("source", "ADV-0004"))
    assert_equal parent.fetch("source_locator"), locator
    assert_equal "reviewed_multi_volume", locator.fetch("strategy")
    assert_equal false, locator.fetch("exact_excerpt")
    assert_equal [17, 25], locator.values_at("start_page", "end_page")
    refute locator.key?("path")
    assert_match(/do not verify coverage/, locator.fetch("warnings").join)
    references = locator.fetch("source_references")
    assert_equal [[19, 20, 3], [23, 24, 5]], references.map { |ref|
      ref.values_at("segment_start_page", "segment_end_page", "page_marker_offset")
    }
    assert_equal FILES.map { |file| File.realpath(File.join(@dir, file)) }, references.map { |ref| ref.fetch("path") }
    references.each do |ref|
      assert_equal Digest::SHA256.file(ref.fetch("path")).hexdigest, ref.fetch("content_sha256")
    end
    pack = AfFrontier::Pack.new(root: @root)
    assert_equal references, pack.sources.find { |source| source["source_id"] == "Book Two" }.fetch("markdown_locators")
    assert_equal [3, 1], pack.manifest.fetch("counts").values_at("source_resolved", "source_unresolved")

    assert_equal "<!-- PDF Page 23 -->\nA20\n", cli_success("source", "ADV-0002", "--emit")
    assert_equal "<!-- PDF Page 28 -->\nB23\n", cli_success("source", "ADV-0003", "--emit")
    other = JSON.parse(cli_success("show", "ADV-0001", "--format", "json"))
    assert_equal "Adventure One", other.fetch("title")
    assert_equal "<!-- Printed Page 10 -->\nAdventure One begins.\n\n" \
      "<!-- PDF Page 111 -->\n<!-- Printed Page 11 -->\nAdventure One continues.\n\n<!-- PDF Page 112 -->\n",
      cli_success("source", "ADV-0001", "--emit")
  end

  # Both excerpt entry points refuse the parent, while metadata bundles retain it.
  def test_parent_exact_excerpt_and_source_bundles_refuse
    build
    message = "Cannot emit exact source for ADV-0004: reviewed across two volumes with no verified single-file excerpt"
    assert_empty cli_refusal(message, "source", "ADV-0004", "--emit")
    %w[json markdown].each do |format|
      path = File.join(@dir, "bundle.#{format}")
      assert_empty cli_refusal(message, "bundle", "--ids", "ADV-0002,ADV-0004",
        "--with-source", "--format", format, "--output", path)
      refute File.exist?(path)
    end
    path = File.join(@dir, "metadata.json")
    cli_success("bundle", "--ids", "ADV-0004", "--format", "json", "--output", path)
    record = JSON.parse(File.read(path)).fetch("adventures").first.fetch("record")
    assert_equal 2, record.dig("source_locator", "source_references").length
  end

  # Bad identity, files, or registry mappings refuse a build before publication.
  def test_refusals_preserve_current
    original_error = 'No configured source segment for "Book Two" contains adventure range 17–25'
    cli_refusal(original_error, *build_args)
    refute File.exist?(@current)
    build
    pointer = File.binread(@current)
    assert_failed_rebuild(pointer, original_error)

    {
      "adventure_id" => "ADV-9999",
      "adventure_title" => "Stale Campaign",
      "source_book" => "Stale Book",
      "start_page" => 18,
      "end_page" => 26,
      "files" => @review.fetch("files").merge("volume-other.md" => @review.dig("files", "volume-two.md"))
        .reject { |file, _sha| file == "volume-two.md" }
    }.each do |field, value|
      File.write(@declaration, JSON.generate(@review.merge(field => value)))
      message = case field
      when "adventure_id" then "Reviewed source Adventure ID not found in catalog"
      when "files" then "Reviewed source files do not match"
      else "Reviewed source declaration does not match catalog identity"
      end
      assert_failed_rebuild(pointer, message, @declaration)
    end
    File.write(@declaration, JSON.generate(@review))

    volume = File.join(@dir, FILES.last)
    original_bytes = File.binread(volume)
    File.binwrite(volume, original_bytes + "\nChanged.\n")
    cli_refusal("source hash changed since build", "doctor")
    assert_failed_rebuild(pointer, "Reviewed source hash mismatch", @declaration)
    File.binwrite(volume, original_bytes)

    aliased_volume = File.join(@dir, FILES.first)
    File.unlink(volume)
    File.link(aliased_volume, volume)
    aliased_files = @review.fetch("files").merge(FILES.last => Digest::SHA256.file(aliased_volume).hexdigest)
    File.write(@declaration, JSON.generate(@review.merge("files" => aliased_files)))
    assert_failed_rebuild(pointer, "Reviewed source files do not match two distinct registry files", @declaration)
    File.unlink(volume)
    File.binwrite(volume, original_bytes)
    File.write(@declaration, JSON.generate(@review))

    original_registry = File.binread(@registry)
    File.binwrite(@registry, original_registry.sub("end_page: 20", "end_page: 22").sub("start_page: 23", "start_page: 22"))
    assert_failed_rebuild(pointer, "requires two unambiguous, nonoverlapping registry segments", @declaration)
    File.binwrite(@registry, original_registry)
    assert_includes cli_success("doctor"), "integrity checks passed"
  end

  private

  # Return the public build arguments with the selected synthetic inputs.
  def build_args
    ["build", "--amc", File.join(FIXTURE, "campaign.xlsx"),
     "--afao", @afao, "--source-registry", @registry, "--corpus-root", @dir]
  end

  # Build with the declaration and return the successful CLI output.
  def build
    cli_success(*build_args, "--reviewed-source", @declaration)
  end

  # Require the public CLI to fail and leave the current pointer byte-identical.
  def assert_failed_rebuild(pointer, message, declaration = nil)
    args = build_args
    args += ["--reviewed-source", declaration] if declaration
    cli_refusal(message, *args)
    assert_equal pointer, File.binread(@current)
  end

  # Return stdout from a CLI invocation, asserting successful termination.
  def cli_success(*args)
    output, error, status = cli(*args)
    assert status.success?, error
    output
  end

  # Return stdout from a CLI refusal, asserting its exit status and message.
  def cli_refusal(message, *args)
    output, error, status = cli(*args)
    assert_equal 1, status.exitstatus, error
    assert_includes error, message
    output
  end

  # Run bin/af-frontier in a separate process. Return stdout, stderr and status.
  def cli(*args)
    env = { "AF_FRONTIER_OUTPUT" => @root }
    Open3.capture3(env, RbConfig.ruby, File.expand_path("../bin/af-frontier", __dir__), *args)
  end
end
