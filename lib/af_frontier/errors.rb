# frozen_string_literal: true

module AfFrontier
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class IntegrityError < Error; end
  class ResolutionError < Error; end
  class QueryError < Error; end
end
