# frozen_string_literal: true

require_relative "test_helper"

class CliTest < Minitest::Test
  def test_help_mentions_output_directory
    out = StringIO.new
    err = StringIO.new
    code = AfFrontier::CLI.new(["help"], out: out, err: err).run
    assert_equal 0, code
    assert_includes out.string, "output/frontier-pack"
  end
end
