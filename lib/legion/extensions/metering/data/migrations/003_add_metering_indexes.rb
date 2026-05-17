# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:metering_records) do
      add_index :worker_id, if_not_exists: true
      add_index :task_id, if_not_exists: true
      add_index :provider, if_not_exists: true
      add_index :recorded_at, if_not_exists: true
    end
  end

  down do
    alter_table(:metering_records) do
      drop_index :worker_id, if_exists: true
      drop_index :task_id, if_exists: true
      drop_index :provider, if_exists: true
      drop_index :recorded_at, if_exists: true
    end
  end
end
