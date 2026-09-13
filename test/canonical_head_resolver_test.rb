# frozen_string_literal: true

require_relative "test_helper"
require "digest"

class CanonicalHeadResolverTest < Minitest::Test
  def test_explicit_amc_wins
    resolver = AfFrontier::CanonicalHeadResolver.new(project_root: TestPaths::FIXTURES)
    result = resolver.resolve(explicit_amc: TestPaths::AMC)
    assert_equal File.realpath(TestPaths::AMC), result.path.to_s
    assert_equal "--amc", result.source
    assert_equal "9.9.9", result.version
    assert_equal Digest::SHA256.file(TestPaths::AMC).hexdigest, result.sha256
  end

  def test_resolves_and_verifies_catalog_head_from_project_state
    Dir.mktmpdir do |dir|
      xlsx_root = File.join(dir, "af-xlsx-data-sources")
      FileUtils.mkdir_p(xlsx_root)
      catalog = File.join(xlsx_root, File.basename(TestPaths::AMC))
      FileUtils.cp(TestPaths::AMC, catalog)
      state = File.join(xlsx_root, "PROJECT_STATE.yml")
      sha = Digest::SHA256.file(catalog).hexdigest
      File.write(state, <<~YAML)
        schema_version: adventurefinder-project-state/v0.2
        catalog_head:
          version: "9.9.9"
          filename: #{File.basename(catalog)}
          sha256: #{sha}
          bytes: #{File.size(catalog)}
      YAML

      resolver = AfFrontier::CanonicalHeadResolver.new(project_root: dir)
      result = resolver.resolve(state_path: state)
      assert_equal File.realpath(catalog), result.path.to_s
      assert_equal "catalog_head", result.role
      assert_equal "9.9.9", result.version
      assert_equal sha, result.sha256
    end
  end

  def test_rejects_project_state_hash_mismatch
    Dir.mktmpdir do |dir|
      catalog = File.join(dir, File.basename(TestPaths::AMC))
      FileUtils.cp(TestPaths::AMC, catalog)
      state = File.join(dir, "PROJECT_STATE.yml")
      File.write(state, <<~YAML)
        schema_version: adventurefinder-project-state/v0.2
        catalog_head:
          version: "9.9.9"
          filename: #{File.basename(catalog)}
          sha256: "#{"0" * 64}"
          bytes: #{File.size(catalog)}
      YAML

      error = assert_raises(AfFrontier::ResolutionError) do
        AfFrontier::CanonicalHeadResolver.new(project_root: dir).resolve(state_path: state)
      end
      assert_includes error.message, "SHA-256 mismatch"
    end
  end

  def test_rejects_unsupported_project_state_schema
    Dir.mktmpdir do |dir|
      state = File.join(dir, "PROJECT_STATE.yml")
      File.write(state, "schema_version: old-schema\ncatalog_head: {}\n")
      error = assert_raises(AfFrontier::ResolutionError) do
        AfFrontier::CanonicalHeadResolver.new(project_root: dir).resolve(state_path: state)
      end
      assert_includes error.message, "Unsupported project-state schema"
    end
  end
end
