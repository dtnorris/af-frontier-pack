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

      ids = adventures.map { |adventure| adventure["adventure_id"] }
      errors << "duplicate Adventure IDs" unless ids.length == ids.uniq.length
      errors << "adventure count mismatch" unless manifest.dig("counts", "adventures") == adventures.length
      errors << "source count mismatch" unless manifest.dig("counts", "sources") == sources.length

      expected_sources = adventures.map { |adventure| adventure.dig("source", "source_id") }.uniq.sort_by(&:to_s)
      actual_sources = sources.map { |source| source["source_id"] }.sort_by(&:to_s)
      errors << "sources.jsonl does not represent exactly the catalog source identities" unless actual_sources == expected_sources

      adventures.each do |adventure|
        id = adventure["adventure_id"]
        errors << "missing adventure_id" if id.nil? || id.to_s.empty?
        ORDINAL.each do |key|
          value = adventure.dig("assessments", key)
          next if value.nil?
          errors << "#{id} #{key}=#{value.inspect} outside 1..5" unless numeric?(value) && value.to_f.between?(1, 5)
        end
        nos = adventure.dig("assessments", "NoS")
        errors << "#{id} NoS must be positive" if nos && (!numeric?(nos) || nos.to_f <= 0)

        locator = adventure["source_locator"] || {}
        if locator["path"] && !File.file?(locator["path"])
          errors << "#{id} source file missing: #{locator['path']}"
        end
      end

      sources.each do |source|
        Array(source["markdown_locators"]).each do |locator|
          path = locator["path"]
          unless path && File.file?(path)
            errors << "#{source['source_id']} source file missing: #{path.inspect}"
            next
          end
          expected_sha = locator["content_sha256"]
          if expected_sha && Digest::SHA256.file(path).hexdigest != expected_sha
            errors << "#{source['source_id']} source hash changed since build: #{path}"
          end
        end
      end

      validate_input_hash(errors, manifest, "amc", "AMC")
      validate_input_hash(errors, manifest, "source_registry", "source registry")
      afao = manifest.dig("inputs", "afao")
      validate_descriptor_hash(errors, afao, "AFAO") if afao

      resolved = adventures.count { |adventure| adventure.dig("source_locator", "path") }
      unresolved = adventures.length - resolved
      errors << "source_resolved count mismatch" unless manifest.dig("counts", "source_resolved") == resolved
      errors << "source_unresolved count mismatch" unless manifest.dig("counts", "source_unresolved") == unresolved

      raise IntegrityError, errors.join("\n") unless errors.empty?
      true
    end

    private

    def validate_input_hash(errors, manifest, key, label)
      descriptor = manifest.dig("inputs", key)
      validate_descriptor_hash(errors, descriptor, label)
    end

    def validate_descriptor_hash(errors, descriptor, label)
      path = descriptor && descriptor["path"]
      sha = descriptor && descriptor["sha256"]
      return unless path && sha

      unless File.file?(path)
        errors << "#{label} file missing: #{path}"
        return
      end
      errors << "#{label} hash changed since build" unless Digest::SHA256.file(path).hexdigest == sha
    end

    def numeric?(value)
      value.is_a?(Numeric) || Float(value)
      true
    rescue ArgumentError, TypeError
      false
    end
  end
end
