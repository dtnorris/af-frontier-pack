# frozen_string_literal: true

require_relative "test_helper"

class SourceRegistryTest < Minitest::Test
  def test_uses_canonical_source_book_as_source_id
    registry = AfFrontier::SourceRegistry.new(path: TestPaths::REGISTRY, corpus_root: TestPaths::CORPUS)
    resolution = registry.resolve("Book One", start_page: 10, end_page: 11)
    assert_equal "Book One", resolution.source_id
    assert_equal "explicit_mapping", resolution.strategy
    assert_equal 0, resolution.page_marker_offset
  end

  def test_resolves_segmented_mapping_by_catalog_page_range
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "part-one.md"), "<!-- PDF Page 10 -->\nOne\n")
      File.write(File.join(dir, "part-two.md"), "<!-- PDF Page 20 -->\nTwo\n")
      registry_path = File.join(dir, "source_registry.yml")
      File.write(registry_path, <<~YAML)
        schema_version: adventurefinder-source-registry/v0.1
        sources:
          Big Book:
            segments:
              - start_page: 1
                end_page: 10
                file: part-one.md
              - start_page: 11
                end_page: 20
                file: part-two.md
                page_marker_offset: "+2"
      YAML

      resolution = AfFrontier::SourceRegistry.new(path: registry_path, corpus_root: dir)
        .resolve("Big Book", start_page: 12, end_page: 14)
      assert_equal "explicit_segment_mapping", resolution.strategy
      assert_equal File.realpath(File.join(dir, "part-two.md")), resolution.markdown_path
      assert_equal 2, resolution.page_marker_offset
      assert_equal 11, resolution.segment_start_page
      assert_equal 20, resolution.segment_end_page
    end
  end

  def test_normalized_filename_fallback_is_explicitly_warned
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Fallback_Book_LLM_Edition.md"), "<!-- PDF Page 1 -->\nText\n")
      registry_path = File.join(dir, "source_registry.yml")
      File.write(registry_path, <<~YAML)
        schema_version: adventurefinder-source-registry/v0.1
        sources: {}
      YAML

      resolution = AfFrontier::SourceRegistry.new(path: registry_path, corpus_root: dir)
        .resolve("Fallback Book", start_page: 1, end_page: 1)
      assert_equal "normalized_filename", resolution.strategy
      assert_equal ["SOURCE_RESOLVED_BY_FILENAME"], resolution.warnings
    end
  end

  def test_rejects_unsigned_page_marker_offset
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "book.md"), "text")
      registry_path = File.join(dir, "source_registry.yml")
      File.write(registry_path, <<~YAML)
        schema_version: adventurefinder-source-registry/v0.1
        sources:
          Book:
            file: book.md
            page_marker_offset: "3"
      YAML

      error = assert_raises(AfFrontier::ConfigurationError) do
        AfFrontier::SourceRegistry.new(path: registry_path, corpus_root: dir)
      end
      assert_includes error.message, "explicitly signed"
    end
  end
end
