# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Actor
        class Cleanup < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/EveryActorRequiresTime
          include Legion::Extensions::Actors::Singleton if defined?(Legion::Extensions::Actors::Singleton)

          def runner_class
            'Legion::Extensions::Metering::Runners::Metering'
          end

          def runner_function
            'cleanup_old_records'
          end

          def time
            86_400 # once per day
          end

          def run_now?
            false
          end

          def use_runner?
            false
          end

          def check_subtask?
            false
          end

          def generate_task?
            false
          end
        end
      end
    end
  end
end
