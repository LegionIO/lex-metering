# frozen_string_literal: true

require 'spec_helper'

require 'legion/extensions/metering/runners/cost_optimizer'

RSpec.describe Legion::Extensions::Metering::Runners::CostOptimizer do
  let(:optimizer) { Class.new { include Legion::Extensions::Metering::Runners::CostOptimizer }.new }

  describe '#analyze_costs' do
    context 'when cost data is available' do
      before do
        allow(optimizer).to receive(:collect_cost_data).and_return([
                                                                     { extension: 'lex-claude', model: 'claude-sonnet-4-6', total_tokens: 50_000,
total_cost: 0.15 },
                                                                     { extension: 'lex-openai', model: 'gpt-4o', total_tokens: 30_000, total_cost: 0.09 }
                                                                   ])
        allow(optimizer).to receive(:generate_recommendations).and_return(
          { recommendations: [{ extension: 'lex-openai', suggested_model: 'gpt-4o-mini', estimated_savings_pct: 60 }] }
        )
      end

      it 'returns analyzed status' do
        result = optimizer.analyze_costs(window_days: 7)
        expect(result[:status]).to eq('analyzed')
      end

      it 'includes cost drivers sorted by cost descending' do
        result = optimizer.analyze_costs(window_days: 7)
        expect(result[:cost_drivers].first[:extension]).to eq('lex-claude')
        expect(result[:cost_drivers].size).to eq(2)
      end

      it 'includes recommendations from LLM' do
        result = optimizer.analyze_costs(window_days: 7)
        expect(result[:recommendations]).to be_an(Array)
        expect(result[:recommendations].first[:suggested_model]).to eq('gpt-4o-mini')
      end

      it 'includes window_days in result' do
        result = optimizer.analyze_costs(window_days: 14)
        expect(result[:window_days]).to eq(14)
      end
    end

    context 'when no cost data is available' do
      before do
        allow(optimizer).to receive(:collect_cost_data).and_return([])
      end

      it 'returns no_data status' do
        result = optimizer.analyze_costs(window_days: 7)
        expect(result[:status]).to eq('no_data')
      end

      it 'returns empty arrays' do
        result = optimizer.analyze_costs(window_days: 7)
        expect(result[:cost_drivers]).to eq([])
        expect(result[:recommendations]).to eq([])
      end
    end

    context 'when generate_recommendations passes caller identity to LLM' do
      let(:llm_spy) do
        Module.new do
          @last_kwargs = nil
          def self.chat(**kwargs)
            @last_kwargs = kwargs
            { content: '{"recommendations":[]}' }
          end

          class << self
            attr_reader :last_kwargs
          end
        end
      end

      before do
        stub_const('Legion::LLM', llm_spy)
        allow(optimizer).to receive(:collect_cost_data).and_return([
                                                                     { extension: 'lex-test', model: 'claude-sonnet-4-6',
total_tokens: 1000, total_cost: 0.01, call_count: 5 }
                                                                   ])
      end

      it 'passes caller identity to Legion::LLM.chat' do
        optimizer.analyze_costs(window_days: 7)
        expect(Legion::LLM.last_kwargs[:caller]).to eq({ extension: 'lex-metering', operation: 'cost_optimization' })
      end
    end

    context 'when top_n limits results' do
      before do
        drivers = (1..15).map do |i|
          { extension: "lex-#{i}", model: "model-#{i}", total_tokens: i * 1000, total_cost: i * 0.01 }
        end
        allow(optimizer).to receive(:collect_cost_data).and_return(drivers)
        allow(optimizer).to receive(:generate_recommendations).and_return({ recommendations: [] })
      end

      it 'limits cost drivers to top_n' do
        result = optimizer.analyze_costs(window_days: 7, top_n: 5)
        expect(result[:cost_drivers].size).to eq(5)
      end

      it 'defaults to top 10' do
        result = optimizer.analyze_costs(window_days: 7)
        expect(result[:cost_drivers].size).to eq(10)
      end
    end
  end
end
