# frozen_string_literal: true

require_relative "test_helper"

class AnalysisOntologyResolverTest < Minitest::Test
  def test_resolves_configured_afao_and_records_declared_version_and_hash
    Dir.mktmpdir do |project_root|
      afao = write_afao(project_root, declared_version: "1.6.1")
      authority = write_authority(project_root, expected_version: "1.6.1")

      resolution = AfFrontier::AnalysisOntologyResolver.new(
        project_root: project_root,
        authority_config: authority
      ).resolve

      assert_equal File.realpath(afao), resolution.path.to_s
      assert_equal "1.6.1", resolution.version
      assert_equal Digest::SHA256.file(afao).hexdigest, resolution.sha256
      assert_equal File.size(afao), resolution.bytes
      assert_equal File.realpath(authority), resolution.source
    end
  end

  def test_fails_closed_when_configured_version_does_not_match_file
    Dir.mktmpdir do |project_root|
      write_afao(project_root, declared_version: "1.6")
      authority = write_authority(project_root, expected_version: "1.6.1")

      error = assert_raises(AfFrontier::ResolutionError) do
        AfFrontier::AnalysisOntologyResolver.new(
          project_root: project_root,
          authority_config: authority
        ).resolve
      end

      assert_includes error.message, "Configured AFAO version mismatch"
    end
  end

  def test_explicit_afao_override_still_records_declared_version
    Dir.mktmpdir do |project_root|
      afao = write_afao(project_root, declared_version: "1.7")

      resolution = AfFrontier::AnalysisOntologyResolver.new(
        project_root: project_root,
        authority_config: File.join(project_root, "missing-authority.yml")
      ).resolve(explicit_afao: afao)

      assert_equal "1.7", resolution.version
      assert_equal "--afao", resolution.source
    end
  end

  private

  def write_afao(project_root, declared_version:)
    root = File.join(project_root, "md-specification-files")
    FileUtils.mkdir_p(root)
    path = File.join(root, "AdventureFinder_Analysis_Ontology_v1.6.1.md")
    File.write(
      path,
      "# AdventureFinder Analysis Ontology\n\n## Version #{declared_version}\n"
    )
    path
  end

  def write_authority(project_root, expected_version:)
    path = File.join(project_root, "authority.yml")
    File.write(
      path,
      <<~YAML
        afao:
          path: md-specification-files/AdventureFinder_Analysis_Ontology_v1.6.1.md
          version: "#{expected_version}"
      YAML
    )
    path
  end
end
