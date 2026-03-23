# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:metering_records) do
      add_column :cost_usd,        Float,  null: false, default: 0.0
      add_column :status,          String, null: true,  size: 50,  index: true
      add_column :event_type,      String, null: true,  size: 100, index: true
      add_column :extension,       String, null: true,  size: 255, index: true
      add_column :runner_function, String, null: true,  size: 255
    end
  end

  down do
    alter_table(:metering_records) do
      drop_column :cost_usd
      drop_column :status
      drop_column :event_type
      drop_column :extension
      drop_column :runner_function
    end
  end
end
