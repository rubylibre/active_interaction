# coding: utf-8

require 'spec_helper'

InteractionWithFilter = Class.new(TestInteraction) do
  float :thing
end

AddInteraction = Class.new(TestInteraction) do
  float :x, :y

  def execute
    x + y
  end
end

InterruptInteraction = Class.new(TestInteraction) do
  model :x, :y,
    class: Object,
    default: nil

  def execute
    compose(AddInteraction, inputs)
  end
end

describe ActiveInteraction::Base do
  include_context 'interactions'

  subject(:interaction) { described_class.new(inputs) }

  describe '.new(inputs = {})' do
    it 'does not allow :_interaction_* as an option' do
      key = :"_interaction_#{SecureRandom.hex}"
      inputs.merge!(key => nil)
      expect do
        interaction
      end.to raise_error ActiveInteraction::InvalidValueError
    end

    it 'does not allow "_interaction_*" as an option' do
      key = "_interaction_#{SecureRandom.hex}"
      inputs.merge!(key => nil)
      expect do
        interaction
      end.to raise_error ActiveInteraction::InvalidValueError
    end

    context 'with invalid inputs' do
      let(:inputs) { nil }

      it 'raises an error' do
        expect { interaction }.to raise_error ArgumentError
      end
    end

    context 'with an attribute' do
      let(:described_class) do
        Class.new(TestInteraction) do
          attr_reader :thing

          validates :thing, presence: true
        end
      end
      let(:thing) { SecureRandom.hex }

      context 'failing validations' do
        before { inputs.merge!(thing: nil) }

        it 'returns an invalid outcome' do
          expect(interaction).to be_invalid
        end
      end

      context 'passing validations' do
        before { inputs.merge!(thing: thing) }

        it 'returns a valid outcome' do
          expect(interaction).to be_valid
        end

        it 'sets the attribute' do
          expect(interaction.thing).to eq thing
        end
      end
    end

    describe 'with a filter' do
      let(:described_class) { InteractionWithFilter }

      context 'failing validations' do
        before { inputs.merge!(thing: thing) }

        context 'with an invalid value' do
          let(:thing) { 'a' }

          it 'sets the attribute to the filtered value' do
            expect(interaction.thing).to equal thing
          end
        end

        context 'without a value' do
          let(:thing) { nil }

          it 'sets the attribute to the filtered value' do
            expect(interaction.thing).to equal thing
          end
        end
      end

      context 'passing validations' do
        before { inputs.merge!(thing: 1) }

        it 'sets the attribute to the filtered value' do
          expect(interaction.thing).to eql 1.0
        end
      end
    end
  end

  describe '.desc' do
    let(:desc) { SecureRandom.hex }

    it 'returns nil' do
      expect(described_class.desc).to be_nil
    end

    it 'returns the description' do
      expect(described_class.desc(desc)).to eq desc
    end

    it 'saves the description' do
      described_class.desc(desc)
      expect(described_class.desc).to eq desc
    end
  end

  describe '.method_missing(filter_type, *args, &block)' do
    it 'raises an error for an invalid filter type' do
      expect do
        Class.new(TestInteraction) do
          not_a_valid_filter_type :thing
        end
      end.to raise_error NoMethodError
    end

    it do
      expect do
        Class.new(TestInteraction) do
          float :_interaction_thing
        end
      end.to raise_error ActiveInteraction::InvalidFilterError
    end

    context 'with a filter' do
      let(:described_class) { InteractionWithFilter }

      it 'adds an attr_reader' do
        expect(interaction).to respond_to :thing
      end

      it 'adds an attr_writer' do
        expect(interaction).to respond_to :thing=
      end
    end

    context 'with multiple filters' do
      let(:described_class) do
        Class.new(TestInteraction) do
          float :thing1, :thing2
        end
      end

      %w(thing1 thing2).each do |thing|
        it "adds an attr_reader for #{thing}" do
          expect(interaction).to respond_to thing
        end

        it "adds an attr_writer for #{thing}" do
          expect(interaction).to respond_to "#{thing}="
        end
      end
    end
  end

  context 'with a filter' do
    let(:described_class) { InteractionWithFilter }
    let(:thing) { rand }

    describe '.run(inputs = {})' do
      it "returns an instance of #{described_class}" do
        expect(outcome).to be_a described_class
      end

      context 'setting the result' do
        let(:described_class) do
          Class.new(TestInteraction) do
            boolean :attribute

            validate do
              @_interaction_result = SecureRandom.hex
              errors.add(:attribute, SecureRandom.hex)
            end
          end
        end

        it 'sets the result to nil' do
          expect(outcome).to be_invalid
          expect(result).to be_nil
        end
      end

      context 'failing validations' do
        it 'returns an invalid outcome' do
          expect(outcome).to_not be_valid
        end

        it 'sets the result to nil' do
          expect(result).to be_nil
        end
      end

      context 'passing validations' do
        before { inputs.merge!(thing: thing) }

        context 'failing runtime validations' do
          before do
            @execute = described_class.instance_method(:execute)
            described_class.send(:define_method, :execute) do
              errors.add(:thing, 'error')
              errors.add_sym(:thing, :error, 'error')
            end
          end

          after do
            silence_warnings do
              described_class.send(:define_method, :execute, @execute)
            end
          end

          it 'returns an invalid outcome' do
            expect(outcome).to be_invalid
          end

          it 'sets the result to nil' do
            expect(result).to be_nil
          end

          it 'has errors' do
            expect(outcome.errors.messages[:thing]).to eq %w(error error)
          end

          it 'has symbolic errors' do
            expect(outcome.errors.symbolic[:thing]).to eq [:error]
          end
        end

        it 'returns a valid outcome' do
          expect(outcome).to be_valid
        end

        it 'sets the result' do
          expect(result[:thing]).to eq thing
        end

        it 'calls ActiveRecord::Base.transaction' do
          allow(ActiveRecord::Base).to receive(:transaction)
          outcome
          expect(ActiveRecord::Base).to have_received(:transaction)
            .with(no_args)
        end
      end
    end

    describe '.run!(inputs = {})' do
      subject(:result) { described_class.run!(inputs) }

      context 'failing validations' do
        it 'raises an error' do
          expect do
            result
          end.to raise_error ActiveInteraction::InvalidInteractionError
        end
      end

      context 'passing validations' do
        before { inputs.merge!(thing: thing) }

        it 'returns the result' do
          expect(result[:thing]).to eq thing
        end
      end
    end
  end

  describe '#inputs' do
    let(:described_class) { InteractionWithFilter }
    let(:other_val) { SecureRandom.hex }
    let(:inputs) { { thing: 1, other: other_val } }

    it 'casts filtered inputs' do
      expect(interaction.inputs[:thing]).to eql 1.0
    end

    it 'strips non-filtered inputs' do
      expect(interaction.inputs).to_not have_key(:other)
    end
  end

  describe '#compose' do
    let(:described_class) { InterruptInteraction }
    let(:x) { rand }
    let(:y) { rand }

    context 'with valid composition' do
      before do
        inputs.merge!(x: x, y: y)
      end

      it 'is valid' do
        expect(outcome).to be_valid
      end

      it 'returns the sum' do
        expect(result).to eq x + y
      end
    end

    context 'with invalid composition' do
      it 'is invalid' do
        expect(outcome).to be_invalid
      end

      it 'has the correct errors' do
        expect(outcome.errors[:base])
          .to match_array ['X is required', 'Y is required']
      end
    end
  end

  describe '#execute' do
    it 'raises an error' do
      expect { interaction.execute }.to raise_error NotImplementedError
    end
  end

  context 'inheritance' do
    let(:described_class) { InteractionWithFilter }

    def filters(klass)
      klass.filters.keys
    end

    it 'includes the filters from the superclass' do
      expect(filters(Class.new(described_class))).to include :thing
    end

    it 'does not mutate the filters on the superclass' do
      Class.new(described_class) { float :other_thing }

      expect(filters(described_class)).to_not include :other_thing
    end
  end

  context 'predicates' do
    let(:described_class) { InteractionWithFilter }

    it 'responds to the predicate' do
      expect(interaction.respond_to?(:thing?)).to be_true
    end

    context 'without a value' do
      it 'returns false' do
        expect(interaction.thing?).to be_false
      end
    end

    context 'with a value' do
      let(:thing) { rand }

      before do
        inputs.merge!(thing: thing)
      end

      it 'returns true' do
        expect(interaction.thing?).to be_true
      end
    end
  end

  describe '.import_filters' do
    shared_context 'import_filters context' do
      let(:klass) { AddInteraction }
      let(:only) { nil }
      let(:except) { nil }

      let(:described_class) do
        interaction = klass
        options = {}
        options[:only] = only unless only.nil?
        options[:except] = except unless except.nil?

        Class.new(TestInteraction) { import_filters interaction, options }
      end
    end

    shared_examples 'import_filters examples' do
      include_context 'import_filters context'

      it 'imports the filters' do
        expect(described_class.filters).to eq klass.filters
          .select { |k, _| only.nil? ? true : only.include?(k) }
          .reject { |k, _| except.nil? ? false : except.include?(k) }
      end

      it 'does not modify the source' do
        filters = klass.filters.dup
        described_class
        expect(klass.filters).to eq filters
      end
    end

    context 'with :only' do
      include_examples 'import_filters examples'

      let(:only) { [:x] }
    end

    context 'with :except' do
      include_examples 'import_filters examples'

      let(:except) { [:x] }
    end

    context 'with :only & :except' do
      include_context 'import_filters context'

      let(:only) { [] }
      let(:except) { [] }

      it 'raises an error' do
        expect { described_class }.to raise_error ArgumentError
      end
    end
  end
end
