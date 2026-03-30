# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Helpers
        module Economics
          PERIOD_DAYS = { daily: 1, weekly: 7, monthly: 30 }.freeze

          def payroll_summary(period: :daily, **)
            return { workers: [], total_cost: 0, avg_productivity: 0 } unless defined?(Legion::Data)

            days = PERIOD_DAYS.fetch(period.to_sym, 1)
            cutoff = Time.now - (days * 86_400)
            ds = Legion::Data.connection[:metering_records].where(Sequel.lit('recorded_at >= ?', cutoff))

            workers = ds.group_and_count(:worker_id).all.map do |row|
              {
                worker_id:  row[:worker_id],
                task_count: row[:count],
                cost:       ds.where(worker_id: row[:worker_id]).sum(:input_tokens).to_f * cost_per_token,
                autonomy:   synapse_autonomy(row[:worker_id])
              }
            end

            total = workers.sum { |w| w[:cost] }
            avg_prod = workers.empty? ? 0 : workers.sum { |w| w[:task_count] } / workers.size.to_f

            { workers: workers, total_cost: total, avg_productivity: avg_prod, period: period }
          end

          def worker_report(worker_id:, period: :daily, **)
            return { salary: 0, overtime: 0, productivity: 0 } unless defined?(Legion::Data)

            days = PERIOD_DAYS.fetch(period.to_sym, 1)
            cutoff = Time.now - (days * 86_400)
            ds = Legion::Data.connection[:metering_records]
                             .where(worker_id: worker_id)
                             .where(Sequel.lit('recorded_at >= ?', cutoff))

            task_count = ds.count
            total_tokens = ds.sum(:input_tokens).to_i + ds.sum(:output_tokens).to_i
            salary = total_tokens.to_f * cost_per_token
            avg_latency = ds.avg(:latency_ms).to_f

            {
              worker_id:      worker_id,
              salary:         salary,
              overtime:       0,
              productivity:   task_count,
              avg_latency:    avg_latency,
              autonomy_level: synapse_autonomy(worker_id),
              period:         period
            }
          end

          def budget_forecast(days: 30, **)
            return { projected_cost: 0, trend: :flat } unless defined?(Legion::Data)

            recent_ds = Legion::Data.connection[:metering_records]
                                    .where(Sequel.lit('recorded_at >= ?', Time.now - 86_400))
            daily_cost = (recent_ds.sum(:input_tokens).to_i + recent_ds.sum(:output_tokens).to_i) *
                         cost_per_token

            { projected_cost: daily_cost * days, daily_average: daily_cost, days: days,
              trend: daily_cost.positive? ? :active : :flat }
          end

          private

          def cost_per_token
            0.000003
          end

          def synapse_autonomy(worker_id)
            return :unknown unless defined?(Legion::Extensions::Synapse)

            Legion::Extensions::Synapse::Client.new.autonomy_level(worker_id: worker_id)
          rescue StandardError => _e
            :unknown
          end
        end
      end
    end
  end
end
