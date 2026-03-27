# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Actor
        class Rollup < Legion::Extensions::Actors::Every
          include Legion::Extensions::Actors::Singleton if defined?(Legion::Extensions::Actors::Singleton)

          def runner_class
            'Legion::Extensions::Metering::Runners::Rollup'
          end

          def runner_function
            'rollup_hour'
          end

          def time
            3600
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
