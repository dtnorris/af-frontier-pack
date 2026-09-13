# frozen_string_literal: true

require_relative "test_helper"

class XlsxCatalogReaderTest < Minitest::Test
  def test_reads_adventure_catalog_and_preserves_blank_values
    rows = AfFrontier::XlsxCatalogReader.new(TestPaths::AMC).rows
    assert_equal 3, rows.length
    assert_equal "ADV-0001", rows[0]["ADV - ID"]
    assert_equal 4, rows[0]["Consequential Player Agency"]
    assert_nil rows[1]["Fantastic Weirdness"]
  end
end
