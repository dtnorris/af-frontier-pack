# frozen_string_literal: true

require_relative "test_helper"

class SourceResolverTest < Minitest::Test
  def test_prefers_printed_markers_when_present
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      AfFrontier::PackBuilder.new(
        amc_path: TestPaths::AMC,
        source_registry: registry,
        afao_path: TestPaths.write_afao(dir),
        output_root: dir
      ).build
      pack = AfFrontier::Pack.new(root: dir)
      text = AfFrontier::SourceResolver.new(pack: pack).emit("ADV-0001")
      assert_includes text, "<!-- Printed Page 10 -->"
      assert_includes text, "Adventure One begins."
      refute_includes text, "<!-- Printed Page 12 -->"
      refute_includes text, "<!-- PDF Page 110 -->"
    end
  end

  def test_applies_registry_offset_to_pdf_fallback_markers
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      AfFrontier::PackBuilder.new(
        amc_path: TestPaths::AMC,
        source_registry: registry,
        afao_path: TestPaths.write_afao(dir),
        output_root: dir
      ).build
      pack = AfFrontier::Pack.new(root: dir)
      record = pack.fetch("ADV-0002")
      assert_equal 3, record.dig("source_locator", "page_marker_offset")

      text = AfFrontier::SourceResolver.new(pack: pack).emit("ADV-0002")
      assert_includes text, "<!-- PDF Page 23 -->"
      refute_includes text, "<!-- PDF Page 24 -->"
    end
  end

  # Cover the final UTF-8 page and the pack's display-specific newline policy.
  def test_emits_a_final_utf8_page_with_one_newline
    Dir.mktmpdir do |dir|
      path = File.join(dir, "source.md")
      File.binwrite(path, "Header é\n> <!-- PAGE: 1 -->\n最後 🐾 \t")
      locator = { "path" => path, "start_page" => 1, "end_page" => 1 }
      pack = { "ADV-0001" => { "source_locator" => locator } }

      assert_equal "> <!-- PAGE: 1 -->\n最後 🐾\n", AfFrontier::SourceResolver.new(pack:).emit("ADV-0001")
    end
  end
end
