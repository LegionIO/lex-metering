# frozen_string_literal: true

require 'spec_helper'

unless defined?(Sequel)
  module Sequel
    def self.lit(_sql, *_args)
      :sequel_lit_placeholder
    end
  end
end

require 'legion/extensions/metering/runners/rollup'

RSpec.describe Legion::Extensions::Metering::Runners::Rollup do
  let(:runner) { Class.new { include Legion::Extensions::Metering::Runners::Rollup }.new }

  describe '#rollup_hour' do
    context 'when data is unavailable' do
      before { hide_const('Legion::Data') }

      it 'returns a skipped hash' do
        result = runner.rollup_hour
        expect(result[:status]).to eq('skipped')
        expect(result[:reason]).to eq('data_unavailable')
      end
    end

    context 'when Legion::Data is defined but connection is nil' do
      before do
        stub_const('Legion::Data', double('Legion::Data', connection: nil, respond_to?: true))
        allow(Legion::Data).to receive(:respond_to?).with(:connection).and_return(true)
      end

      it 'returns a skipped hash' do
        result = runner.rollup_hour
        expect(result[:status]).to eq('skipped')
      end
    end

    context 'when data is available' do
      let(:fixed_hour) { Time.utc(2026, 3, 25, 10, 0, 0) }
      let(:previous_hour) { fixed_hour - 3600 }

      let(:sample_records) do
        [
          { worker_id: 'w1', provider: 'anthropic', model_id: 'claude-sonnet-4-6',
            input_tokens: 100, output_tokens: 50, thinking_tokens: 10,
            cost_usd: 0.005, latency_ms: 800 },
          { worker_id: 'w1', provider: 'anthropic', model_id: 'claude-sonnet-4-6',
            input_tokens: 200, output_tokens: 80, thinking_tokens: 0,
            cost_usd: 0.009, latency_ms: 600 }
        ]
      end

      let(:records_ds) do
        ds = double('records_dataset')
        allow(ds).to receive(:where).and_return(ds)
        allow(ds).to receive(:count).and_return(sample_records.size)
        allow(ds).to receive(:group_by) { |&blk| sample_records.group_by(&blk) }
        ds
      end

      let(:rollup_ds) do
        ds = double('rollup_dataset')
        allow(ds).to receive(:where).and_return(ds)
        allow(ds).to receive(:first).and_return(nil)
        allow(ds).to receive(:insert)
        allow(ds).to receive(:update)
        ds
      end

      let(:connection) do
        conn = double('connection')
        allow(conn).to receive(:[]).with(:metering_records).and_return(records_ds)
        allow(conn).to receive(:[]).with(:metering_hourly_rollup).and_return(rollup_ds)
        allow(conn).to receive(:table_exists?).with(:metering_records).and_return(true)
        allow(conn).to receive(:table_exists?).with(:metering_hourly_rollup).and_return(true)
        conn
      end

      before do
        stub_const('Legion::Data', double('Legion::Data', connection: connection))
        allow(Legion::Data).to receive(:respond_to?).with(:connection).and_return(true)
        stub_const('Legion::Logging', double('Legion::Logging'))
        allow(Legion::Logging).to receive(:info)

        allow(Time).to receive(:now).and_return(fixed_hour)
      end

      it 'returns a result hash with rolled_up, hour, and raw_records keys' do
        result = runner.rollup_hour
        expect(result).to have_key(:rolled_up)
        expect(result).to have_key(:hour)
        expect(result).to have_key(:raw_records)
      end

      it 'uses the previous completed hour when no hour is given' do
        result = runner.rollup_hour
        expect(result[:hour]).to eq(previous_hour.iso8601)
      end

      it 'uses the provided hour when given' do
        explicit_hour = Time.utc(2026, 3, 25, 8, 0, 0)
        result = runner.rollup_hour(hour: explicit_hour)
        expect(result[:hour]).to eq(explicit_hour.iso8601)
      end

      it 'reports raw_records count' do
        result = runner.rollup_hour
        expect(result[:raw_records]).to eq(2)
      end

      it 'inserts rollup rows for each group' do
        expect(rollup_ds).to receive(:insert).once
        runner.rollup_hour
      end

      it 'updates existing rollup row when conflict exists' do
        existing_row = { id: 99, worker_id: 'w1', provider: 'anthropic', model_id: 'claude-sonnet-4-6' }
        allow(rollup_ds).to receive(:first).and_return(existing_row)
        allow(rollup_ds).to receive(:where).with(
          worker_id: 'w1', provider: 'anthropic', model_id: 'claude-sonnet-4-6', hour: anything
        ).and_return(rollup_ds)
        allow(rollup_ds).to receive(:where).with(id: 99).and_return(rollup_ds)

        expect(rollup_ds).to receive(:update).once
        runner.rollup_hour
      end

      it 'logs an info message' do
        expect(Legion::Logging).to receive(:info).with(a_string_including('[metering] rollup_hour:'))
        runner.rollup_hour
      end
    end
  end

  describe '#purge_raw_records' do
    context 'when data is unavailable' do
      before { hide_const('Legion::Data') }

      it 'returns a skipped hash' do
        result = runner.purge_raw_records
        expect(result[:status]).to eq('skipped')
        expect(result[:reason]).to eq('data_unavailable')
      end
    end

    context 'when Legion::Data is defined but connection is nil' do
      before do
        stub_const('Legion::Data', double('Legion::Data', connection: nil))
        allow(Legion::Data).to receive(:respond_to?).with(:connection).and_return(true)
      end

      it 'returns a skipped hash' do
        result = runner.purge_raw_records
        expect(result[:status]).to eq('skipped')
      end
    end

    context 'when data is available' do
      let(:filtered_ds) do
        ds = double('filtered_ds')
        allow(ds).to receive(:delete).and_return(15)
        ds
      end

      let(:records_ds) do
        ds = double('records_ds')
        allow(ds).to receive(:where).and_return(filtered_ds)
        ds
      end

      let(:connection) do
        conn = double('connection')
        allow(conn).to receive(:[]).with(:metering_records).and_return(records_ds)
        allow(conn).to receive(:table_exists?).with(:metering_records).and_return(true)
        conn
      end

      before do
        stub_const('Legion::Data', double('Legion::Data', connection: connection))
        allow(Legion::Data).to receive(:respond_to?).with(:connection).and_return(true)
        stub_const('Legion::Logging', double('Legion::Logging'))
        allow(Legion::Logging).to receive(:info)
      end

      it 'returns purged count, retention_days, and cutoff' do
        result = runner.purge_raw_records
        expect(result[:purged]).to eq(15)
        expect(result[:retention_days]).to eq(7)
        expect(result[:cutoff]).to be_a(String)
      end

      it 'defaults retention_days to 7' do
        result = runner.purge_raw_records
        expect(result[:retention_days]).to eq(7)
      end

      it 'accepts a custom retention_days' do
        result = runner.purge_raw_records(retention_days: 30)
        expect(result[:retention_days]).to eq(30)
      end

      it 'returns cutoff as an ISO8601 string' do
        result = runner.purge_raw_records
        expect { Time.parse(result[:cutoff]) }.not_to raise_error
      end

      it 'logs an info message' do
        expect(Legion::Logging).to receive(:info).with(a_string_including('[metering] purge_raw_records:'))
        runner.purge_raw_records
      end
    end
  end

  describe 'method availability' do
    it 'responds to rollup_hour' do
      expect(runner).to respond_to(:rollup_hour)
    end

    it 'responds to purge_raw_records' do
      expect(runner).to respond_to(:purge_raw_records)
    end
  end
end
