# lex-metering

LLM cost metering for LegionIO. Records token usage, latency, and routing metrics per task for cost attribution, budget forecasting, and intelligent model routing.

**Ruby >= 3.4** | **License**: MIT | **Author**: [@Esity](https://github.com/Esity)

## Installation

Included with the LegionIO framework. No separate installation needed.

```ruby
# Gemfile
gem 'lex-metering'
```

## Architecture

```
Legion::Extensions::Metering
├── Runners/
│   ├── Metering         # record, worker_costs, team_costs, routing_stats, cleanup_old_records
│   ├── CostOptimizer    # analyze_costs (LLM-powered model rightsizing)
│   └── Rollup           # rollup_hour, purge_raw_records
├── Actors/
│   ├── Cleanup          # Daily (86400s) — prunes records older than 90 days
│   ├── CostOptimizer    # Weekly (604800s) — generates model rightsizing recommendations
│   └── Rollup           # Hourly (3600s) — aggregates raw records into hourly summaries
├── Helpers/
│   └── Economics        # payroll_summary, worker_report, budget_forecast
└── Data/Migrations/
    ├── 001              # metering_records table
    ├── 002              # trace columns (cost_usd, status, event_type, extension, runner_function)
    └── 003              # indexes (worker_id, task_id, provider, recorded_at)
```

## Usage

### Recording Metrics

```ruby
Legion::Extensions::Metering::Runners::Metering.record(
  worker_id:      'worker-abc',
  task_id:        42,
  provider:       'anthropic',
  model_id:       'claude-sonnet-4-6',
  input_tokens:   1000,
  output_tokens:  500,
  thinking_tokens: 200,
  latency_ms:     1200,
  wall_clock_ms:  1500,
  cpu_time_ms:    80,
  cost_usd:       0.0051,
  routing_reason: 'cost_optimization',
  extension:      'lex-developer',
  runner_function: 'generate_code',
  status:         'success',
  event_type:     'llm_completion'
)
```

### Querying Costs

```ruby
# Per-worker costs (daily/weekly/monthly)
Legion::Extensions::Metering::Runners::Metering.worker_costs(
  worker_id: 'worker-abc',
  period:    'weekly'
)
# => { worker_id:, period:, total_tokens:, input_tokens:, output_tokens:,
#      thinking_tokens:, total_calls:, avg_latency_ms:, by_provider:, by_model: }

# Per-team costs
Legion::Extensions::Metering::Runners::Metering.team_costs(
  team: 'engineering',
  period: 'monthly'
)
# => { team:, period:, worker_count:, total_tokens:, total_calls:, by_worker: }
```

### Routing Statistics

```ruby
Legion::Extensions::Metering::Runners::Metering.routing_stats(worker_id: 'worker-abc')
# => { by_routing_reason: [...], by_provider: [...], by_model: [...],
#      avg_latency_by_provider: [{ provider: 'anthropic', avg_latency: 820.0 }] }
```

### Hourly Rollup

Raw records are aggregated hourly into `metering_hourly_rollup` for efficient reporting:

```ruby
# Manually trigger (normally runs via actor)
Legion::Extensions::Metering::Runners::Rollup.rollup_hour
# => { rolled_up: 15, hour: "2026-05-17T10:00:00Z", raw_records: 340 }

# Purge rolled-up raw records (default: 7 days retention)
Legion::Extensions::Metering::Runners::Rollup.purge_raw_records(retention_days: 7)
# => { purged: 2400, retention_days: 7, cutoff: "2026-05-10T11:00:00Z" }
```

### Cost Optimization

Weekly LLM-powered analysis identifies model rightsizing opportunities:

```ruby
Legion::Extensions::Metering::Runners::CostOptimizer.analyze_costs(window_days: 7, top_n: 10)
# => { status: 'analyzed', window_days: 7, cost_drivers: [...],
#      recommendations: [{ extension: 'lex-developer', current_model: 'claude-opus-4-6',
#                          suggested_model: 'claude-sonnet-4-6', rationale: '...',
#                          estimated_savings_pct: 80 }] }
```

Built-in rate table (per 1M tokens):

| Provider | Model | Rate |
|----------|-------|------|
| Anthropic | claude-opus-4-6 | $15.00 |
| Anthropic | claude-sonnet-4-6 | $3.00 |
| Anthropic | claude-haiku-4-5 | $0.25 |
| OpenAI | gpt-4o | $5.00 |
| OpenAI | gpt-4o-mini | $0.15 |
| OpenAI | gpt-4.1 | $2.00 |
| Bedrock | default | $3.00 |
| Azure AI | default | $3.00 |

### Economics Helper

Labor economics reporting for digital worker cost attribution:

```ruby
include Legion::Extensions::Metering::Helpers::Economics

payroll_summary(period: :weekly)
# => { workers: [{ worker_id:, task_count:, cost:, autonomy: }], total_cost:, avg_productivity: }

worker_report(worker_id: 'worker-abc', period: :daily)
# => { worker_id:, salary:, overtime:, productivity:, avg_latency:, autonomy_level: }

budget_forecast(days: 30)
# => { projected_cost: 4.50, daily_average: 0.15, days: 30, trend: :active }
```

## Database Schema

### `metering_records`

| Column | Type | Description |
|--------|------|-------------|
| `id` | Integer (PK) | Auto-increment primary key |
| `worker_id` | String(36) | Digital worker ID |
| `task_id` | Integer | Legion task ID |
| `provider` | String(100) | LLM provider name |
| `model_id` | String(255) | Model identifier |
| `input_tokens` | Integer | Prompt tokens |
| `output_tokens` | Integer | Completion tokens |
| `thinking_tokens` | Integer | Reasoning tokens |
| `total_tokens` | Integer | Sum of all token types |
| `input_context_bytes` | Integer | Raw context size in bytes |
| `latency_ms` | Integer | LLM API round-trip time |
| `wall_clock_ms` | Integer | Total wall-clock time |
| `cpu_time_ms` | Integer | CPU time consumed |
| `external_api_calls` | Integer | Non-LLM external API calls |
| `routing_reason` | String(255) | Model/provider selection rationale |
| `cost_usd` | Float | Estimated cost in USD |
| `status` | String(50) | Pipeline status at time of record |
| `event_type` | String(100) | Event type for audit correlation |
| `extension` | String(255) | Calling extension name |
| `runner_function` | String(255) | Calling runner function |
| `recorded_at` | DateTime | Timestamp (indexed) |

Indexes: `worker_id`, `task_id`, `provider`, `recorded_at`, `status`, `event_type`, `extension`

### `metering_hourly_rollup`

Aggregated hourly summaries grouped by worker/provider/model. One row per unique combination per hour, upserted on each rollup cycle.

## Record Retention

| Actor | Interval | Retention | Description |
|-------|----------|-----------|-------------|
| Cleanup | Daily | 90 days | Prunes raw `metering_records` older than cutoff |
| Rollup | Hourly | — | Aggregates into `metering_hourly_rollup` |
| Purge | On-demand | 7 days | Removes rolled-up raw records via `purge_raw_records` |

```ruby
# Manual cleanup
Legion::Extensions::Metering::Runners::Metering.cleanup_old_records(retention_days: 90)
# => { purged: 1234, retention_days: 90, cutoff: 2026-02-16 00:00:00 UTC }
```

## Integration Points

| System | Interface | Description |
|--------|-----------|-------------|
| MCP | `legion.routing_stats` | Tool for querying routing statistics |
| REST API | `GET /api/metering` | Returns routing stats and recent records |
| CLI | `legion worker costs` | Worker cost attribution from terminal |
| lex-llm-gateway | Shared table | Gateway publishes metering events over AMQP |
| legion-data | Migrations 021, 046 | Archive table and hourly rollup DDL |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Related

- [LegionIO](https://github.com/LegionIO/LegionIO) — Framework
- [legion-data](https://github.com/LegionIO/legion-data) — Persistence layer
- [lex-llm-gateway](https://github.com/LegionIO/lex-llm-gateway) — Gateway that publishes metering events over AMQP
