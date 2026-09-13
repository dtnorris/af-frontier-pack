# frozen_string_literal: true

require_relative "test_helper"

class JsonlTest < Minitest::Test
  def test_round_trips_unicode_independent_of_process_locale
    Dir.mktmpdir do |dir|
      path = File.join(dir, "unicode.jsonl")
      records = [{ "title" => "Moria: Shadow of Khazad-dûm" }]
      AfFrontier::Jsonl.write(path, records)
      assert_equal records, AfFrontier::Jsonl.read(path).to_a
    end
  end
end
