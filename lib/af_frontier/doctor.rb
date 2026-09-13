# frozen_string_literal: true

require "digest"
require "set"

module AfFrontier
  class Doctor
    ORDINAL = %w[CE EE SIE IE PPSE TC LFS RSMD SO CPA SR DHI FW GMPB GMID PBS GMBS].freeze

    def initialize(pack: Pack.new)
      @pack = pack
    end

    def check
      errors = []
      manifest = @pack.manifest
      adventures = @pack.adventures
      sources = @pack.sources

      ids = adventures.map { |a| a["adventure_id"] }
      errors << "duplicate Adventure IDs" unless ids.length == ids.uniq.length
      errors << "adventure count mismatch" unless manifest.dig("counts", "adventures") == adventures.length
      errors << "source count mismatch" unless manifest.dig("counts", "sources") == sources.length

      adventures.each do |adv|
        id = adv["adventure_id"]
        errors << "missing adventure_id" if id.nil? || id.to_s.empty?
        ORDINAL.each do |key|
          value = adv.dig("assessments", key)
          next if value.nil?
          errors << "#{id} #{key}=#{value.inspect} outside 1..5" unless numeric?(value) && value.to_f.between?(1, 5)
        end
        nos = adv.dig("assessments", "NoS")
        errors << "#{id} NoS must be positive" if nos && (!numeric?(nos) || nos.to_f <= 0)

        locator = adv["source_locator"] || {}
        if locator["path"] && !File.file?(locator["path"])
          errors << "#{id} source file missing: #{locator['path']}"
        end
      end

      amc_path = manifest.dig("inputs", "amc", "path")
      amc_sha = manifest.dig("inputs", "amc", "sha256")
      if amc_path && File.file?(amc_path) && amc_sha
        actual = Digest::SHA256.file(amc_path).hexdigest
        errors << "AMC hash changed since build" unless actual == amc_sha
      end

      raise IntegrityError, errors.join("\n") unless errors.empty?
      true
    end

    private

    def numeric?(value)
      value.is_a?(Numeric) || Float(value)
      true
    rescue ArgumentError, TypeError
      false
    end
  end
end
