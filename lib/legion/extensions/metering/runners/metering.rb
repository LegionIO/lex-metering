# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Runners
        module Metering
          def record(worker_id: nil, task_id: nil, provider: nil, model_id: nil,
                     input_tokens: 0, output_tokens: 0, thinking_tokens: 0,
                     input_context_bytes: 0, latency_ms: 0, routing_reason: nil,
                     wall_clock_ms: 0, cpu_time_ms: 0, external_api_calls: 0, **)
            record = {
              worker_id:           worker_id,
              task_id:             task_id,
              provider:            provider,
              model_id:            model_id,
              input_tokens:        input_tokens,
              output_tokens:       output_tokens,
              thinking_tokens:     thinking_tokens,
              total_tokens:        input_tokens + output_tokens + thinking_tokens,
              input_context_bytes: input_context_bytes,
              latency_ms:          latency_ms,
              wall_clock_ms:       wall_clock_ms,
              cpu_time_ms:         cpu_time_ms,
              external_api_calls:  external_api_calls,
              routing_reason:      routing_reason,
              recorded_at:         Time.now.utc
            }

            Legion::Data.connection[:metering_records].insert(record) if defined?(Legion::Data) && Legion::Data.connection
            Legion::Logging.debug "[metering] recorded: provider=#{provider} model=#{model_id} " \
                                  "tokens=#{record[:total_tokens]} latency=#{latency_ms}ms wall_clock=#{wall_clock_ms}ms"
            record
          end

          def worker_costs(worker_id:, period: 'daily', **)
            ds = Legion::Data.connection[:metering_records].where(worker_id: worker_id)

            case period
            when 'daily'
              ds = ds.where { recorded_at >= Sequel.lit("CURRENT_TIMESTAMP - INTERVAL '1 day'") }
            when 'weekly'
              ds = ds.where { recorded_at >= Sequel.lit("CURRENT_TIMESTAMP - INTERVAL '7 days'") }
            when 'monthly'
              ds = ds.where { recorded_at >= Sequel.lit("CURRENT_TIMESTAMP - INTERVAL '30 days'") }
            end

            {
              worker_id:       worker_id,
              period:          period,
              total_tokens:    ds.sum(:total_tokens) || 0,
              input_tokens:    ds.sum(:input_tokens) || 0,
              output_tokens:   ds.sum(:output_tokens) || 0,
              thinking_tokens: ds.sum(:thinking_tokens) || 0,
              total_calls:     ds.count,
              avg_latency_ms:  ds.avg(:latency_ms)&.round(1) || 0,
              by_provider:     ds.group_and_count(:provider).all,
              by_model:        ds.group_and_count(:model_id).all
            }
          end

          def team_costs(team:, period: 'daily', **)
            workers = Legion::Data::Model::DigitalWorker.where(team: team).select_map(:worker_id)
            ds = Legion::Data.connection[:metering_records].where(worker_id: workers)

            {
              team:         team,
              period:       period,
              worker_count: workers.size,
              total_tokens: ds.sum(:total_tokens) || 0,
              total_calls:  ds.count,
              by_worker:    ds.group_and_count(:worker_id).all
            }
          end

          def routing_stats(worker_id: nil, **)
            ds = Legion::Data.connection[:metering_records]
            ds = ds.where(worker_id: worker_id) if worker_id

            {
              by_routing_reason:       ds.group_and_count(:routing_reason).all,
              by_provider:             ds.group_and_count(:provider).all,
              by_model:                ds.group_and_count(:model_id).all,
              avg_latency_by_provider: ds.group(:provider).select_append { avg(latency_ms).as(avg_latency) }.all
            }
          end
        end
      end
    end
  end
end
