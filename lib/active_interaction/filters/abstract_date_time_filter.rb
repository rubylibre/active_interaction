# coding: utf-8

module ActiveInteraction
  # @abstract
  #
  # Common logic for filters that handle `Date`, `DateTime`, and `Time`
  #   objects.
  #
  # @private
  class AbstractDateTimeFilter < AbstractFilter
    alias_method :_cast, :cast
    private :_cast

    def cast(value)
      case value
      when *klasses
        value
      when String
        convert(value)
      else
        super
      end
    end

    private

    def convert(value)
      if format?
        klass.strptime(value, format)
      else
        klass.parse(value)
      end
    rescue ArgumentError
      _cast(value)
    end

    # @return [String]
    def format
      options.fetch(:format)
    end

    # @return [Boolean]
    def format?
      options.key?(:format)
    end

    # @return [Array<Class>]
    def klasses
      [klass]
    end
  end
end
