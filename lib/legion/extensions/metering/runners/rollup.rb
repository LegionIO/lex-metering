# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Runners
        module Rollup
          extend self

          def rollup_hour(hour: nil, **)
            return { status: 'skipped', reason: 'data_unavailable' } unless data_available?

            hour = resolve_hour(hour)
            hour_end = hour + 3600

            records_ds = Legion::Data.connection[:metering_records]
                                     .where(::Sequel.lit('recorded_at >= ? AND recorded_at < ?', hour, hour_end))

            raw_count = records_ds.count
            groups = records_ds.group_by { |r| [r[:worker_id], r[:provider], r[:model_id]] }

            rollup_dataset = Legion::Data.connection[:metering_hourly_rollup]
            rolled_up = 0

            groups.each do |(w, p, m), rows|
              rollup_row = build_rollup_row(w, p, m, hour, rows)
              existing = rollup_dataset.where(worker_id: w, provider: p, model_id: m, hour: hour).first

              if existing
                rollup_dataset.where(id: existing[:id]).update(
                  rollup_row.except(:worker_id, :provider, :model_id, :hour)
                )
              else
                rollup_dataset.insert(rollup_row)
              end

              rolled_up += 1
            end

            log.info("[metering] rollup_hour: hour=#{hour.iso8601} groups=#{rolled_up} raw_records=#{raw_count}")
            { rolled_up: rolled_up, hour: hour.iso8601, raw_records: raw_count }
          end

          def purge_raw_records(retention_days: 7, **)
            return { status: 'skipped', reason: 'data_unavailable' } unless data_available?(:metering_records)

            cutoff = Time.now.utc - (retention_days * 86_400)
            count = Legion::Data.connection[:metering_records]
                                .where(::Sequel.lit('recorded_at < ?', cutoff))
                                .delete

            log.info("[metering] purge_raw_records: purged=#{count} retention_days=#{retention_days} cutoff=#{cutoff.iso8601}")
            { purged: count, retention_days: retention_days, cutoff: cutoff.iso8601 }
          end

          private

          def data_available?(table = nil)
            return false unless defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection # rubocop:disable Legion/Extension/RunnerReturnHash

            if table
              Legion::Data.connection.table_exists?(table)
            else
              Legion::Data.connection.table_exists?(:metering_records) &&
                Legion::Data.connection.table_exists?(:metering_hourly_rollup)
            end
          end

          def resolve_hour(hour)
            return hour if hour # rubocop:disable Legion/Extension/RunnerReturnHash

            now = Time.now.utc
            floored = Time.utc(now.year, now.month, now.day, now.hour)
            floored - 3600
          end

          def build_rollup_row(worker_id, provider, model_id, hour, rows)
            latencies = rows.filter_map { |r| r[:latency_ms] }
            avg_latency = latencies.empty? ? 0 : (latencies.sum.to_f / latencies.size).round(2)

            {
              worker_id:             worker_id,
              provider:              provider,
              model_id:              model_id,
              hour:                  hour,
              total_input_tokens:    rows.sum { |r| r[:input_tokens].to_i },
              total_output_tokens:   rows.sum { |r| r[:output_tokens].to_i },
              total_thinking_tokens: rows.sum { |r| r[:thinking_tokens].to_i },
              total_calls:           rows.size,
              total_cost_usd:        rows.sum { |r| r[:cost_usd].to_f }.round(6),
              avg_latency_ms:        avg_latency,
              created_at:            Time.now.utc
            }
          end
        end
      end
    end
  end
end
