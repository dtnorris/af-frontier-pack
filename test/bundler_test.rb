# frozen_string_literal: true

require_relative "test_helper"

class BundlerTest < Minitest::Test
  def test_writes_bundle_to_absolute_path
    Dir.mktmpdir do |dir|
      registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
      pack_root = File.join(dir, "pack")
      AfFrontier::PackBuilder.new(amc_path: TestPaths::AMC, source_registry: registry, output_root: pack_root).build
      pack = AfFrontier::Pack.new(root: pack_root)
      dest = File.join(dir, "bundle.md")
      path = AfFrontier::Bundler.new(pack: pack).write(ids: ["ADV-0001", "ADV-0002"], path: dest)
      assert path.absolute?
      assert File.file?(path)
      assert_includes File.read(path), "ADV-0001"
      assert_includes File.read(path), "ADV-0002"
    end
  end
end
