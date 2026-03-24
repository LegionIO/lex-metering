# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Actor
        class CostOptimizer < Legion::Extensions::Actors::Every
          include Legion::Extensions::Actors::Singleton if defined?(Legion::Extensions::Actors::Singleton)

          def runner_class
            'Legion::Extensions::Metering::Runners::CostOptimizer'
          end

          def runner_function
            'analyze_costs'
          end

          def time
            604_800 # once per week
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
