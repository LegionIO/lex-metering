# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:metering_records) do
      primary_key :id
      String  :worker_id,           null: true, size: 36, index: true
      Integer :task_id,             null: true,             index: true
      String  :provider,            null: true,  size: 100, index: true
      String  :model_id,            null: true,  size: 255
      Integer :input_tokens,        null: false, default: 0
      Integer :output_tokens,       null: false, default: 0
      Integer :thinking_tokens,     null: false, default: 0
      Integer :total_tokens,        null: false, default: 0
      Integer :input_context_bytes, null: false, default: 0
      Integer :latency_ms,          null: false, default: 0
      Integer :wall_clock_ms,       null: false, default: 0
      Integer :cpu_time_ms,         null: false, default: 0
      Integer :external_api_calls,  null: false, default: 0
      String  :routing_reason,      null: true,  size: 255
      DateTime :recorded_at, null: false, default: Sequel::CURRENT_TIMESTAMP, index: true
    end
  end

  down do
    drop_table :metering_records
  end
end
