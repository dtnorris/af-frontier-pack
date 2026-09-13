# frozen_string_literal: true

require_relative "test_helper"

class PackBuilderTest < Minitest::Test
  def test_builds_deterministic_pack_with_nulls
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      manifest = AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: dir).build
      pack = AfFrontier::Pack.new(root: dir)

      assert_equal 3, manifest.dig("counts", "adventures")
      assert_equal 2, manifest.dig("counts", "sources")
      assert_equal "9.9.9", manifest.dig("inputs", "amc", "version")
      assert_nil pack.fetch("ADV-0002").dig("assessments", "FW")
      assert_includes pack.fetch("ADV-0002").dig("assessment_status", "unassessed"), "FW"
      assert AfFrontier::Doctor.new(pack: pack).check
    end
  end
end
