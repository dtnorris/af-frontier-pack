# frozen_string_literal: true

require_relative "test_helper"

class SourceResolverTest < Minitest::Test
  def test_prefers_printed_markers_when_present
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: dir).build
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
      AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: dir).build
      pack = AfFrontier::Pack.new(root: dir)
      record = pack.fetch("ADV-0002")
      assert_equal 3, record.dig("source_locator", "page_marker_offset")

      text = AfFrontier::SourceResolver.new(pack: pack).emit("ADV-0002")
      assert_includes text, "<!-- PDF Page 23 -->"
      refute_includes text, "<!-- PDF Page 24 -->"
    end
  end
end
