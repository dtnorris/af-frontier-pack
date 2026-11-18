# frozen_string_literal: true

module AfFrontier
  # Selects the shared Markdown owner when an operation needs it.
  module SourceMarkdownOwner
    API_VERSION = "af-source-md/v0.1"

    module_function

    # Return the owner module for the process. Invalid or unsupported selection
    # raises ConfigurationError, including when an installed copy is available.
    def load!
      if ENV.key?("AF_SOURCE_MD_ROOT")
        root = ENV.fetch("AF_SOURCE_MD_ROOT")
        unless !root.strip.empty? && File.absolute_path(root) == root && File.directory?(root)
          raise ConfigurationError, "AF_SOURCE_MD_ROOT must select an existing absolute owner directory"
        end

        entry = File.join(root, "lib", "af_source_md.rb")
        raise ConfigurationError, "Missing selected source Markdown owner: #{entry}" unless File.file?(entry)
        require entry
        unless defined?(AFSourceMD::ROOT) && AFSourceMD::ROOT == File.realpath(root)
          raise ConfigurationError, "Selected source Markdown owner identity does not match #{root}"
        end
      else
        require "af_source_md"
      end

      unless defined?(AFSourceMD::API_VERSION) && AFSourceMD::API_VERSION == API_VERSION &&
             defined?(AFSourceMD::SourceResolver) && defined?(AFSourceMD::SourceDocument)
        raise ConfigurationError, "Unsupported source Markdown owner API; expected #{API_VERSION}"
      end

      AFSourceMD
    rescue ConfigurationError
      raise
    rescue LoadError, SyntaxError, StandardError => error
      raise ConfigurationError, "Cannot load source Markdown owner: #{error.message}"
    end
  end
end
