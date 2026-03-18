# frozen_string_literal: true

require 'spec_helper'

unless defined?(Sequel)
  module Sequel
    def self.lit(_sql, *_args)
      :sequel_lit_placeholder
    end
  end
end

require 'legion/extensions/metering/runners/metering'

RSpec.describe Legion::Extensions::Metering::Runners::Metering do
  let(:runner) { Class.new { include Legion::Extensions::Metering::Runners::Metering }.new }

  describe '#record' do
    before do
      stub_const('Legion::Logging', double('Legion::Logging'))
      allow(Legion::Logging).to receive(:debug)
    end

    it 'returns a record hash with computed total_tokens' do
      result = runner.record(
        provider:        'anthropic',
        model_id:        'claude-opus-4-6',
        input_tokens:    100,
        output_tokens:   50,
        thinking_tokens: 10,
        latency_ms:      800
      )

      expect(result[:total_tokens]).to eq(160)
      expect(result[:provider]).to eq('anthropic')
      expect(result[:model_id]).to eq('claude-opus-4-6')
      expect(result[:latency_ms]).to eq(800)
    end

    it 'defaults token counts to zero when not provided' do
      result = runner.record(provider: 'openai', model_id: 'gpt-4o')
      expect(result[:total_tokens]).to eq(0)
      expect(result[:input_tokens]).to eq(0)
      expect(result[:output_tokens]).to eq(0)
      expect(result[:thinking_tokens]).to eq(0)
    end

    it 'sets recorded_at to a UTC Time' do
      result = runner.record
      expect(result[:recorded_at]).to be_a(Time)
      expect(result[:recorded_at].utc?).to be true
    end

    it 'does not write to database directly' do
      hide_const('Legion::Data')
      result = runner.record(provider: 'anthropic', model_id: 'claude-opus-4-6')
      expect(result[:provider]).to eq('anthropic')
    end

    it 'logs a debug message' do
      expect(Legion::Logging).to receive(:debug).with(
        a_string_including('[metering] recorded:')
      )
      runner.record(provider: 'anthropic', model_id: 'claude-opus-4-6', total_tokens: 0, latency_ms: 200)
    end
  end

  describe '#worker_costs' do
    let(:by_provider_result) { [{ provider: 'anthropic', count: 5 }] }
    let(:by_model_result)    { [{ model_id: 'claude-opus-4-6', count: 5 }] }

    let(:worker_dataset) do
      ds = double('worker_dataset')
      allow(ds).to receive(:where).and_return(ds)
      allow(ds).to receive(:sum).with(:total_tokens).and_return(1000)
      allow(ds).to receive(:sum).with(:input_tokens).and_return(600)
      allow(ds).to receive(:sum).with(:output_tokens).and_return(300)
      allow(ds).to receive(:sum).with(:thinking_tokens).and_return(100)
      allow(ds).to receive(:count).and_return(5)
      allow(ds).to receive(:avg).with(:latency_ms).and_return(750.5)
      allow(ds).to receive(:group_and_count).with(:provider).and_return(
        double('by_provider', all: by_provider_result)
      )
      allow(ds).to receive(:group_and_count).with(:model_id).and_return(
        double('by_model', all: by_model_result)
      )
      ds
    end

    let(:connection) do
      conn = double('connection')
      allow(conn).to receive(:[]).with(:metering_records).and_return(worker_dataset)
      conn
    end

    before do
      stub_const('Legion::Data', double('Legion::Data', connection: connection))
      stub_const('Legion::Logging', double('Legion::Logging'))
      allow(Legion::Logging).to receive(:debug)
    end

    it 'returns aggregated metrics for the worker' do
      result = runner.worker_costs(worker_id: 'worker-abc-123')

      expect(result[:worker_id]).to eq('worker-abc-123')
      expect(result[:period]).to eq('daily')
      expect(result[:total_tokens]).to eq(1000)
      expect(result[:input_tokens]).to eq(600)
      expect(result[:output_tokens]).to eq(300)
      expect(result[:thinking_tokens]).to eq(100)
      expect(result[:total_calls]).to eq(5)
      expect(result[:avg_latency_ms]).to eq(750.5)
      expect(result[:by_provider]).to eq(by_provider_result)
      expect(result[:by_model]).to eq(by_model_result)
    end

    it 'uses daily period by default' do
      result = runner.worker_costs(worker_id: 'worker-abc-123')
      expect(result[:period]).to eq('daily')
    end

    it 'accepts weekly period' do
      result = runner.worker_costs(worker_id: 'worker-abc-123', period: 'weekly')
      expect(result[:period]).to eq('weekly')
    end

    it 'accepts monthly period' do
      result = runner.worker_costs(worker_id: 'worker-abc-123', period: 'monthly')
      expect(result[:period]).to eq('monthly')
    end

    it 'returns zero for total_tokens when sum returns nil' do
      allow(worker_dataset).to receive(:sum).with(:total_tokens).and_return(nil)
      result = runner.worker_costs(worker_id: 'worker-abc-123')
      expect(result[:total_tokens]).to eq(0)
    end

    it 'returns zero for avg_latency_ms when avg returns nil' do
      allow(worker_dataset).to receive(:avg).with(:latency_ms).and_return(nil)
      result = runner.worker_costs(worker_id: 'worker-abc-123')
      expect(result[:avg_latency_ms]).to eq(0)
    end
  end

  describe '#team_costs' do
    let(:worker_ids) { %w[worker-1 worker-2 worker-3] }
    let(:by_worker_result) { worker_ids.map { |id| { worker_id: id, count: 2 } } }

    let(:team_dataset) do
      ds = double('team_dataset')
      allow(ds).to receive(:where).and_return(ds)
      allow(ds).to receive(:sum).with(:total_tokens).and_return(3000)
      allow(ds).to receive(:count).and_return(6)
      allow(ds).to receive(:group_and_count).with(:worker_id).and_return(
        double('by_worker', all: by_worker_result)
      )
      ds
    end

    let(:connection) do
      conn = double('connection')
      allow(conn).to receive(:[]).with(:metering_records).and_return(team_dataset)
      conn
    end

    let(:digital_worker_model) do
      model = double('DigitalWorker')
      scope = double('scope')
      allow(model).to receive(:where).with(team: 'platform').and_return(scope)
      allow(scope).to receive(:select_map).with(:worker_id).and_return(worker_ids)
      model
    end

    before do
      conn = connection
      data_module = Module.new
      data_module.const_set(:Model, Module.new)
      data_module.define_singleton_method(:connection) { conn }
      stub_const('Legion::Data', data_module)
      stub_const('Legion::Data::Model::DigitalWorker', digital_worker_model)
      stub_const('Legion::Logging', double('Legion::Logging'))
      allow(Legion::Logging).to receive(:debug)
    end

    it 'returns aggregated metrics for the team' do
      result = runner.team_costs(team: 'platform')

      expect(result[:team]).to eq('platform')
      expect(result[:period]).to eq('daily')
      expect(result[:worker_count]).to eq(3)
      expect(result[:total_tokens]).to eq(3000)
      expect(result[:total_calls]).to eq(6)
      expect(result[:by_worker]).to eq(by_worker_result)
    end

    it 'uses daily period by default' do
      result = runner.team_costs(team: 'platform')
      expect(result[:period]).to eq('daily')
    end

    it 'accepts a custom period' do
      result = runner.team_costs(team: 'platform', period: 'monthly')
      expect(result[:period]).to eq('monthly')
    end

    it 'returns zero for total_tokens when sum returns nil' do
      allow(team_dataset).to receive(:sum).with(:total_tokens).and_return(nil)
      result = runner.team_costs(team: 'platform')
      expect(result[:total_tokens]).to eq(0)
    end

    it 'reflects the number of workers found' do
      allow(digital_worker_model).to receive(:where).with(team: 'platform').and_return(
        double('scope', select_map: %w[worker-only-one])
      )
      result = runner.team_costs(team: 'platform')
      expect(result[:worker_count]).to eq(1)
    end
  end

  describe '#routing_stats' do
    let(:by_routing_reason_result) { [{ routing_reason: 'local', count: 3 }] }
    let(:by_provider_result)       { [{ provider: 'anthropic', count: 5 }] }
    let(:by_model_result)          { [{ model_id: 'claude-opus-4-6', count: 5 }] }
    let(:avg_latency_result)       { [{ provider: 'anthropic', avg_latency: 820.0 }] }

    let(:base_dataset) do
      ds = double('base_dataset')
      allow(ds).to receive(:group_and_count).with(:routing_reason).and_return(
        double('by_routing_reason', all: by_routing_reason_result)
      )
      allow(ds).to receive(:group_and_count).with(:provider).and_return(
        double('by_provider', all: by_provider_result)
      )
      allow(ds).to receive(:group_and_count).with(:model_id).and_return(
        double('by_model', all: by_model_result)
      )
      allow(ds).to receive(:group).with(:provider).and_return(
        double('grouped', select_append: double('appended', all: avg_latency_result))
      )
      ds
    end

    let(:connection) do
      conn = double('connection')
      allow(conn).to receive(:[]).with(:metering_records).and_return(base_dataset)
      conn
    end

    before do
      stub_const('Legion::Data', double('Legion::Data', connection: connection))
      stub_const('Legion::Logging', double('Legion::Logging'))
      allow(Legion::Logging).to receive(:debug)
    end

    it 'returns routing breakdowns without worker filter' do
      result = runner.routing_stats

      expect(result[:by_routing_reason]).to eq(by_routing_reason_result)
      expect(result[:by_provider]).to eq(by_provider_result)
      expect(result[:by_model]).to eq(by_model_result)
      expect(result[:avg_latency_by_provider]).to eq(avg_latency_result)
    end

    it 'applies worker_id filter when provided' do
      filtered_ds = double('filtered_dataset')
      allow(base_dataset).to receive(:where).with(worker_id: 'worker-abc').and_return(filtered_ds)

      allow(filtered_ds).to receive(:group_and_count).with(:routing_reason).and_return(
        double('by_routing_reason', all: [])
      )
      allow(filtered_ds).to receive(:group_and_count).with(:provider).and_return(
        double('by_provider', all: [])
      )
      allow(filtered_ds).to receive(:group_and_count).with(:model_id).and_return(
        double('by_model', all: [])
      )
      allow(filtered_ds).to receive(:group).with(:provider).and_return(
        double('grouped', select_append: double('appended', all: []))
      )

      result = runner.routing_stats(worker_id: 'worker-abc')

      expect(result).to have_key(:by_routing_reason)
      expect(result).to have_key(:by_provider)
      expect(result).to have_key(:by_model)
      expect(result).to have_key(:avg_latency_by_provider)
    end

    it 'does not filter by worker_id when not provided' do
      expect(base_dataset).not_to receive(:where)
      runner.routing_stats
    end

    it 'returns a hash with the four expected keys' do
      result = runner.routing_stats
      expect(result.keys).to contain_exactly(
        :by_routing_reason,
        :by_provider,
        :by_model,
        :avg_latency_by_provider
      )
    end
  end

  describe '#cleanup_old_records' do
    let(:filtered_dataset) do
      ds = double('filtered_dataset')
      allow(ds).to receive(:delete).and_return(42)
      ds
    end

    let(:metering_dataset) do
      ds = double('metering_dataset')
      allow(ds).to receive(:where).and_return(filtered_dataset)
      ds
    end

    let(:connection) do
      conn = double('connection')
      allow(conn).to receive(:[]).with(:metering_records).and_return(metering_dataset)
      conn
    end

    before do
      stub_const('Legion::Data', double('Legion::Data', connection: connection))
      stub_const('Legion::Logging', double('Legion::Logging'))
      allow(Legion::Logging).to receive(:info)
    end

    it 'deletes records older than the cutoff and returns purge count' do
      result = runner.cleanup_old_records
      expect(result[:purged]).to eq(42)
    end

    it 'uses 90-day retention by default' do
      result = runner.cleanup_old_records
      expect(result[:retention_days]).to eq(90)
    end

    it 'accepts a custom retention_days parameter' do
      result = runner.cleanup_old_records(retention_days: 30)
      expect(result[:retention_days]).to eq(30)
    end

    it 'returns a cutoff Time in the result' do
      result = runner.cleanup_old_records
      expect(result[:cutoff]).to be_a(Time)
    end

    it 'logs an info message' do
      expect(Legion::Logging).to receive(:info).with(a_string_including('[metering] cleanup:'))
      runner.cleanup_old_records
    end

    it 'returns purged: 0 when Legion::Data is not available' do
      hide_const('Legion::Data')
      result = runner.cleanup_old_records
      expect(result[:purged]).to eq(0)
      expect(result[:cutoff]).to be_nil
    end
  end
end
