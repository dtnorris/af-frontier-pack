# frozen_string_literal: true

require_relative "test_helper"

class CanonicalHeadResolverTest < Minitest::Test
  def test_explicit_amc_wins
    resolver = AfFrontier::CanonicalHeadResolver.new(project_root: TestPaths::FIXTURES)
    result = resolver.resolve(explicit_amc: TestPaths::AMC)
    assert_equal File.realpath(TestPaths::AMC), result.path.to_s
    assert_equal "--amc", result.source
  end

  def test_resolves_named_catalog_head_from_state_manifest
    Dir.mktmpdir do |dir|
      state = File.join(dir, "PROJECT_STATE.yml")
      File.write(state, "catalog_head:
  path: #{TestPaths::AMC}
")
      resolver = AfFrontier::CanonicalHeadResolver.new(project_root: dir)
      result = resolver.resolve(state_path: state)
      assert_equal File.realpath(TestPaths::AMC), result.path.to_s
      assert_equal "catalog_head", result.role
    end
  end
end
