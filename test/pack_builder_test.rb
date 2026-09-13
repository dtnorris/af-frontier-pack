# frozen_string_literal: true

require_relative "test_helper"

class PackBuilderTest < Minitest::Test
  def test_builds_deterministic_pack_with_nulls_and_catalog_source_identities
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      manifest = AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: dir).build
      pack = AfFrontier::Pack.new(root: dir)

      assert_equal 3, manifest.dig("counts", "adventures")
      assert_equal 2, manifest.dig("counts", "sources")
      assert_equal 3, manifest.dig("counts", "source_resolved")
      assert_equal 0, manifest.dig("counts", "source_unresolved")
      assert_equal "9.9.9", manifest.dig("inputs", "amc", "version")
      assert_equal AfFrontier::SourceRegistry::REGISTRY_SCHEMA_VERSION,
                   manifest.dig("inputs", "source_registry", "schema_version")
      assert_nil pack.fetch("ADV-0002").dig("assessments", "FW")
      assert_includes pack.fetch("ADV-0002").dig("assessment_status", "unassessed"), "FW"
      assert_equal "Book One", pack.fetch("ADV-0001").dig("source", "source_id")
      assert_equal ["Book One", "Book Two"], pack.sources.map { |source| source["source_id"] }
      assert pack.sources.all? { |source| source["resolution_status"] == "resolved" }
      assert_nil pack.fetch("ADV-0001")["parentage"]
      assert AfFrontier::Doctor.new(pack: pack).check
    end
  end
end
