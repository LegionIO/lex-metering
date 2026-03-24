# frozen_string_literal: true

# Stub the actor base class before requiring the real actor
unless defined?(Legion::Extensions::Actors::Every)
  module Legion
    module Extensions
      module Actors
        class Every; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

unless defined?(Legion::Extensions::Actors::Singleton)
  module Legion
    module Extensions
      module Actors
        module Singleton
          def self.included(base)
            base.prepend(ExecutionGuard)
          end

          def singleton_role
            self.class.name&.gsub('::', '_')&.downcase || 'unknown'
          end

          module ExecutionGuard
          end
        end
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/every'
$LOADED_FEATURES << 'legion/extensions/actors/singleton'

require_relative '../../../../../lib/legion/extensions/metering/actors/cleanup'

RSpec.describe Legion::Extensions::Metering::Actor::Cleanup do
  subject(:actor) { described_class.new }

  describe '#runner_class' do
    it 'returns the metering runner class string' do
      expect(actor.runner_class).to eq('Legion::Extensions::Metering::Runners::Metering')
    end
  end

  describe '#runner_function' do
    it 'returns cleanup_old_records' do
      expect(actor.runner_function).to eq('cleanup_old_records')
    end
  end

  describe '#time' do
    it 'returns 86_400 (once per day)' do
      expect(actor.time).to eq(86_400)
    end
  end

  describe '#run_now?' do
    it 'returns false' do
      expect(actor.run_now?).to be false
    end
  end

  describe '#use_runner?' do
    it 'returns false' do
      expect(actor.use_runner?).to be false
    end
  end

  describe '#check_subtask?' do
    it 'returns false' do
      expect(actor.check_subtask?).to be false
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(actor.generate_task?).to be false
    end
  end

  describe 'singleton enforcement' do
    it 'includes Singleton mixin when available' do
      expect(described_class.ancestors).to include(Legion::Extensions::Actors::Singleton)
    end

    it 'has a singleton_role derived from class name' do
      expect(actor.singleton_role).to eq('legion_extensions_metering_actor_cleanup')
    end
  end
end
