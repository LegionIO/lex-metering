# lex-metering: LLM Cost Metering for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-core/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Captures LLM token usage metrics per task for cost attribution and intelligent routing. Records input/output/thinking tokens, latency, wall-clock time, CPU time, external API call counts, cost in USD, trace context (extension, runner_function, event_type, status), and routing reason per metered call. Supports per-worker, per-team, and aggregate routing statistics queries. Hourly rollup to a summary table for reporting efficiency.

## Gem Info

- **Gem name**: `lex-metering`
- **Version**: `0.1.11`
- **Module**: `Legion::Extensions::Metering`
- **Ruby**: `>= 3.4`
- **License**: MIT
- **GitHub**: https://github.com/LegionIO/lex-metering

## File Structure

```
lib/legion/extensions/metering/
  version.rb
  actors/
    cleanup.rb       # Every actor (86400s/daily): calls cleanup_old_records
    cost_optimizer.rb # Every actor (604800s/weekly): calls analyze_costs; Singleton mixin
    rollup.rb        # Every actor (3600s/hourly): calls rollup_hour; run_now? false
  data/
    migrations/
      001_add_metering_records.rb  # Creates metering_records table (base schema)
      002_add_trace_columns.rb     # Adds cost_usd, status, event_type, extension, runner_function
  runners/
    metering.rb       # record, worker_costs, team_costs, routing_stats, cleanup_old_records
    cost_optimizer.rb # analyze_costs (LLM-powered model rightsizing recommendations)
    rollup.rb         # rollup_hour, purge_raw_records
```

## Database Schema (`metering_records`)

| Column | Type | Description |
|--------|------|-------------|
| `worker_id` | String(36) | Digital worker ID (nullable for non-worker tasks) |
| `task_id` | Integer | Legion task ID |
| `provider` | String(100) | LLM provider (e.g., 'anthropic', 'openai', 'bedrock') |
| `model_id` | String(255) | Model identifier |
| `input_tokens` | Integer | Prompt tokens |
| `output_tokens` | Integer | Completion tokens |
| `thinking_tokens` | Integer | Thinking/reasoning tokens (Anthropic extended thinking) |
| `total_tokens` | Integer | Sum of all token types |
| `input_context_bytes` | Integer | Raw context size in bytes |
| `latency_ms` | Integer | LLM API round-trip time |
| `wall_clock_ms` | Integer | Total wall-clock time for the task |
| `cpu_time_ms` | Integer | CPU time consumed |
| `external_api_calls` | Integer | Non-LLM external API calls made |
| `routing_reason` | String(255) | Why this model/provider was chosen |
| `cost_usd` | Float | Estimated cost in USD (default: 0.0) |
| `status` | String(50) | Pipeline status at time of record |
| `event_type` | String(100) | Event type for SIEM/audit correlation |
| `extension` | String(255) | Calling extension name |
| `runner_function` | String(255) | Calling runner function name |
| `recorded_at` | DateTime | Timestamp (indexed) |

## Runner Methods

| Method | Parameters | Returns |
|--------|-----------|---------|
| `record` | All schema fields as kwargs | Record hash (also inserted to DB when connected) |
| `worker_costs` | `worker_id:`, `period: 'daily'` | Aggregated token/call/latency metrics |
| `team_costs` | `team:`, `period: 'daily'` | Team-wide aggregation across all team workers |
| `routing_stats` | `worker_id: nil` | Breakdowns by routing_reason, provider, model, avg latency |
| `cleanup_old_records` | `retention_days: 90` | Deletes records older than cutoff |

`period` values: `'daily'`, `'weekly'`, `'monthly'`

### Rollup (`Runners::Rollup`)

`rollup_hour` — groups `metering_records` by worker/provider/model for the current hour into `metering_hourly_rollup` table with upsert semantics (one row per worker+provider+model+hour).

`purge_raw_records(retention_days: 7)` — deletes raw `metering_records` older than the retention window after they have been rolled up.

### CostOptimizer (`Runners::CostOptimizer`)

`analyze_costs(window_days: 7, top_n: 10)` — aggregates cost drivers from `metering_records` for the past `window_days` days. Calls `Legion::LLM.chat` (with `caller: { extension: 'lex-metering', operation: 'cost_optimization' }`) to generate model rightsizing recommendations. Returns `{ status:, cost_drivers:, recommendations: }`.

Built-in rate table (per 1M tokens): Anthropic claude-opus-4-6 $15, claude-sonnet-4-6 $3, claude-haiku-4-5 $0.25; OpenAI gpt-4o $5, gpt-4o-mini $0.15; Bedrock/Azure default $3.

## Actors

| Actor | Interval | Behaviour |
|-------|----------|-----------|
| `Cleanup` | 86400s daily | `cleanup_old_records`; `use_runner? false` |
| `CostOptimizer` | 604800s weekly | `analyze_costs`; `use_runner? false`; Singleton mixin |
| `Rollup` | 3600s hourly | `rollup_hour`; `run_now? false` |

## Integration Points

- **legion-data**: `data_required? false` — loads without DB. `record` returns hash for RMQ publishing; query methods require `Legion::Data`.
- **LegionIO MCP**: `legion.routing_stats` MCP tool calls `routing_stats` runner
- **REST API**: `GET /api/tasks/:id` includes a `:metering` block when lex-metering data exists for the task
- **Digital Workers**: `legion worker costs` CLI command delegates to `worker_costs` runner
- **lex-llm-gateway**: MeteringWriter actor writes to the same `metering_records` table

## Development Notes

- Actor module is `module Actor` (singular) per framework convention
- `routing_stats` uses `select_append { avg(latency_ms).as(avg_latency) }` — Sequel virtual row syntax
- Time interval filtering uses `Sequel.lit('recorded_at >= ?', cutoff)` with Ruby `Time` arithmetic for cross-database compatibility
- `CostOptimizer` actor includes `Legion::Extensions::Actors::Singleton` when available to prevent duplicate weekly runs in a cluster

---

**Maintained By**: Matthew Iverson (@Esity)
