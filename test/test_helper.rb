# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "af_frontier"

module TestPaths
  ROOT = File.expand_path(__dir__)
  FIXTURES = File.join(ROOT, "fixtures")
  AMC = File.join(FIXTURES, "5e_Adventure_Master_Catalog_9.9.9.xlsx")
  REGISTRY = File.join(FIXTURES, "source_registry.yml")
  CORPUS = File.join(FIXTURES, "corpus")

  def self.write_afao(dir, version: "1.6.1")
    path = File.join(dir, "AdventureFinder_Analysis_Ontology_v#{version}.md")
    File.write(path, "# AdventureFinder Analysis Ontology\n\n## Version #{version}\n")
    path
  end
end
