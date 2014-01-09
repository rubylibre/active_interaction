# coding: utf-8

require 'active_support/core_ext/hash/indifferent_access'

module ActiveInteraction
  # @abstract Subclass and override {#execute} to implement a custom
  #   ActiveInteraction::Base class.
  #
  # @example
  #   class ExampleInteraction < ActiveInteraction::Base
  #     # Required
  #     integer :a, :b
  #
  #     # Optional
  #     integer :c, default: nil
  #
  #     def execute
  #       sum = a + b
  #       c.nil? ? sum : sum + c
  #     end
  #   end
  #
  #   outcome = ExampleInteraction.run(a: 1, b: 2, c: 3)
  #   if outcome.valid?
  #     p outcome.result
  #   else
  #     p outcome.errors
  #   end
  class Base
    include ActiveModelable
    include Runnable

    class << self
      include Hashable
      include Missable
    end

    validate :input_errors

    # @param inputs [Hash{Symbol => Object}] Attribute values to set.
    #
    # @private
    def initialize(inputs = {})
      fail ArgumentError, 'inputs must be a hash' unless inputs.is_a?(Hash)

      process_inputs(inputs.symbolize_keys)
    end

    # @!method execute
    #   @abstract
    #
    #   Runs the business logic associated with the interaction. The method is
    #     only run when there are no validation errors. The return value is
    #     placed into {#result}. This method must be overridden in the
    #     subclass. This method is run in a transaction if ActiveRecord is
    #     available.
    #
    #   @raise (see ActiveInteraction::Runnable#execute)
    loop

    # Returns the inputs provided to {.run} or {.run!} after being cast based
    #   on the filters in the class.
    #
    # @return [Hash{Symbol => Object}] All inputs passed to {.run} or {.run!}.
    #
    # @since 0.6.0
    def inputs
      self.class.filters.each_with_object({}) do |filter, h|
        h[filter.name] = public_send(filter.name)
      end
    end

    # Get or set the description.
    #
    # @example
    #   core.desc
    #   # => nil
    #   core.desc('descriptive!')
    #   core.desc
    #   # => "descriptive!"
    #
    # @param desc [String, nil] what to set the description to
    #
    # @return [String, nil] the description
    #
    # @since 0.8.0
    def self.desc(desc = nil)
      if desc.nil?
        unless instance_variable_defined?(:@_interaction_desc)
          @_interaction_desc = nil
        end
      else
        @_interaction_desc = desc
      end

      @_interaction_desc
    end

    # Get all the filters defined on this interaction.
    #
    # @return [Filters]
    #
    # @since 0.6.0
    def self.filters
      @_interaction_filters ||= Filters.new
    end

    # @private
    def self.method_missing(*args, &block)
      super do |klass, names, options|
        fail InvalidFilterError, 'missing attribute name' if names.empty?

        names.each do |attribute|
          fail InvalidFilterError, attribute.inspect if reserved?(attribute)

          filter = klass.new(attribute, options, &block)
          filters.add(filter)
          attr_accessor filter.name

          # This isn't required, but it makes invalid defaults raise errors on
          #   class definition instead of on execution.
          filter.default if filter.default?
        end
      end
    end

    # @!method self.run(*)
    #   Runs validations and if there are no errors it will call {#execute}.
    #
    #   @param (see ActiveInteraction::Base#initialize)
    #
    #   @return (see ActiveInteraction::Runnable::ClassMethods#run)
    loop

    # @!method self.run!(*)
    #   Like {.run} except that it returns the value of {#execute} or raises an
    #     exception if there were any validation errors.
    #
    #   @param (see ActiveInteraction::Base#initialize)
    #
    #   @return (see ActiveInteraction::Runnable::ClassMethods#run!)
    #
    #   @raise (see ActiveInteraction::Runnable::ClassMethods#run!)
    loop

    private

    def process_inputs(inputs)
      inputs.each do |key, value|
        fail InvalidValueError, key.inspect if self.class.reserved?(key)

        instance_variable_set("@#{key}", value)
      end

      self.class.filters.each do |filter|
        begin
          public_send("#{filter.name}=", filter.clean(inputs[filter.name]))
        rescue InvalidValueError, MissingValueError
          # Validators (#input_errors) will add errors if appropriate.
        end
      end
    end

    def input_errors
      Validation.validate(self.class.filters, inputs).each do |error|
        errors.add_sym(*error)
      end
    end

    def self.inherited(klass)
      new_filters = Filters.new
      filters.each { |f| new_filters.add(f) }

      klass.instance_variable_set(:@_interaction_filters, new_filters)
    end

    def self.reserved?(symbol)
      symbol.to_s.start_with?('_interaction_')
    end
  end
end
