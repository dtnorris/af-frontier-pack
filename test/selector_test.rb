# frozen_string_literal: true

require_relative "test_helper"

class SelectorTest < Minitest::Test
  def test_and_filters_and_does_not_match_null
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: dir).build
      pack = AfFrontier::Pack.new(root: dir)
      rows = AfFrontier::Selector.new(pack: pack).select(["GMPB<=2", "CPA>=4"])
      assert_equal ["ADV-0001"], rows.map { |r| r["adventure_id"] }

      weird = AfFrontier::Selector.new(pack: pack).select(["FW<=2"])
      refute_includes weird.map { |r| r["adventure_id"] }, "ADV-0002"
    end
  end
end
