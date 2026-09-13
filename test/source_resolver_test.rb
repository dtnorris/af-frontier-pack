# frozen_string_literal: true

require_relative "test_helper"

class SourceResolverTest < Minitest::Test
  def test_emits_exact_page_slice_when_page_basis_is_explicit
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: dir).build
      pack = AfFrontier::Pack.new(root: dir)
      text = AfFrontier::SourceResolver.new(pack: pack).emit("ADV-0001")
      assert_includes text, "<!-- PDF Page 10 -->"
      assert_includes text, "Adventure One begins."
      refute_includes text, "<!-- PDF Page 12 -->"
    end
  end
end
