# frozen_string_literal: true

module AfFrontier
  class Selector
    FIELD_READERS = {
      "ADV_ID" => ->(a) { a["adventure_id"] },
      "PLAYED" => ->(a) { a["played"] },
      "NoS" => ->(a) { a.dig("assessments", "NoS") },
      "LEVEL_START" => ->(a) { a.dig("assessments", "LSLE", "start") },
      "LEVEL_END" => ->(a) { a.dig("assessments", "LSLE", "end") }
    }.merge(
      %w[CE EE SIE IE PPSE TC LFS RSMD SO CPA SR DHI FW GMPB GMID PBS GMBS].to_h do |key|
        [key, ->(a) { a.dig("assessments", key) }]
      end
    ).freeze

    QUERY = /\A\s*([A-Za-z_]+)\s*(<=|>=|!=|=|<|>)\s*(.+?)\s*\z/

    def initialize(pack: Pack.new)
      @pack = pack
    end

    def select(conditions)
      predicates = Array(conditions).map { |condition| compile(condition) }
      @pack.adventures.select { |adv| predicates.all? { |p| p.call(adv) } }
    end

    private

    def compile(text)
      match = QUERY.match(text.to_s)
      raise QueryError, "Invalid --where expression: #{text.inspect}" unless match
      field, operator, raw_target = match.captures
      canonical = FIELD_READERS.key?(field) ? field : FIELD_READERS.keys.find { |k| k.casecmp?(field) }
      raise QueryError, "Unsupported field #{field.inspect}" unless canonical
      reader = FIELD_READERS.fetch(canonical)
      target = parse_target(raw_target)

      lambda do |adventure|
        value = reader.call(adventure)
        next false if value.nil?
        compare(value, operator, target)
      end
    end

    def parse_target(raw)
      stripped = raw.strip
      return true if stripped.casecmp?("true")
      return false if stripped.casecmp?("false")
      return stripped.to_i if stripped.match?(/\A-?\d+\z/)
      return stripped.to_f if stripped.match?(/\A-?(?:\d+\.\d*|\d*\.\d+)\z/)
      stripped.sub(/\A(["'])(.*)\1\z/, '\\2')
    end

    def compare(value, operator, target)
      left, right = coerce_pair(value, target)
      case operator
      when "=" then left == right
      when "!=" then left != right
      when "<" then left < right
      when "<=" then left <= right
      when ">" then left > right
      when ">=" then left >= right
      else false
      end
    rescue ArgumentError
      false
    end

    def coerce_pair(value, target)
      if value.is_a?(Numeric) && target.is_a?(Numeric)
        [value.to_f, target.to_f]
      else
        [value, target]
      end
    end
  end
end
