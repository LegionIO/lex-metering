# frozen_string_literal: true

module Legion
  module Extensions
    module Metering
      module Runners
        module CostOptimizer
          def analyze_costs(window_days: 7, top_n: 10)
            drivers = collect_cost_data(window_days: window_days)
            return { status: 'no_data', window_days: window_days, cost_drivers: [], recommendations: [] } if drivers.empty?

            top_drivers = drivers.sort_by { |d| -(d[:total_cost] || 0) }.first(top_n)
            recommendations = generate_recommendations(top_drivers)

            {
              status:          'analyzed',
              window_days:     window_days,
              cost_drivers:    top_drivers,
              recommendations: recommendations[:recommendations] || []
            }
          end

          private

          def collect_cost_data(window_days:)
            return [] unless defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection

            cutoff = Time.now.utc - (window_days * 86_400)
            ds = Legion::Data.connection[:metering_records]
                             .where(::Sequel.lit('recorded_at >= ?', cutoff))

            grouped = ds.group(:provider, :model_id)
                        .select_append do
                          [sum(total_tokens).as(total_tokens),
                           sum(input_tokens).as(input_tokens),
                           sum(output_tokens).as(output_tokens),
                           count(Sequel.lit('*')).as(call_count)]
                        end

            grouped.all.map do |row|
              {
                extension:    row[:provider],
                model:        row[:model_id],
                total_tokens: row[:total_tokens] || 0,
                total_cost:   estimate_cost(row[:provider], row[:model_id], row[:total_tokens] || 0),
                call_count:   row[:call_count] || 0
              }
            end
          rescue StandardError
            []
          end

          def estimate_cost(provider, model, total_tokens)
            rate = cost_rate(provider, model)
            (total_tokens * rate / 1_000_000.0).round(4)
          end

          def cost_rate(provider, model)
            rates = {
              'anthropic' => { 'claude-opus-4-6' => 15.0, 'claude-sonnet-4-6' => 3.0, 'claude-haiku-4-5' => 0.25 },
              'openai'    => { 'gpt-4o' => 5.0, 'gpt-4o-mini' => 0.15, 'gpt-4.1' => 2.0 },
              'bedrock'   => { 'default' => 3.0 },
              'azure-ai'  => { 'default' => 3.0 }
            }
            provider_rates = rates[provider&.to_s] || {}
            provider_rates[model&.to_s] || provider_rates['default'] || 1.0
          end

          def generate_recommendations(drivers)
            return { recommendations: [] } unless defined?(Legion::LLM)

            prompt = build_recommendation_prompt(drivers)
            result = Legion::LLM.chat(message: prompt)
            ::JSON.parse(result[:content] || '{}', symbolize_names: true)
          rescue StandardError
            { recommendations: [] }
          end

          def build_recommendation_prompt(drivers)
            lines = drivers.map do |d|
              "#{d[:extension]}/#{d[:model]}: #{d[:total_tokens]} tokens, $#{d[:total_cost]}, #{d[:call_count]} calls"
            end

            <<~PROMPT
              Analyze these LLM cost drivers from the past week and recommend model rightsizing.
              Focus on cases where a cheaper model could handle the workload.

              #{lines.join("\n")}

              Return JSON: { "recommendations": [{ "extension": "...", "current_model": "...", "suggested_model": "...", "rationale": "...", "estimated_savings_pct": N }] }
            PROMPT
          end
        end
      end
    end
  end
end
