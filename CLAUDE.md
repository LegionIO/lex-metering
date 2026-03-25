# lex-metering: LLM Cost Metering for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-core/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Captures LLM token usage metrics per task for cost attribution and intelligent routing. Records input/output/thinking tokens, latency, wall-clock time, CPU time, external API call counts, and routing reason per metered call. Supports per-worker, per-team, and aggregate routing statistics queries.

## Gem Info

- **Gem name**: `lex-metering`
- **Version**: `0.1.6`
- **Module**: `Legion::Extensions::Metering`
- **Ruby**: `>= 3.4`
- **License**: MIT
- **GitHub**: https://github.com/LegionIO/lex-metering

## File Structure

```
lib/legion/extensions/metering/
  version.rb
  actors/
    cleanup.rb    # Every actor (86400s/daily): calls cleanup_old_records
  data/
    migrations/
      001_add_metering_records.rb  # Creates metering_records table
  runners/
    metering.rb   # record, worker_costs, team_costs, routing_stats, cleanup_old_records
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
| `recorded_at` | DateTime | Timestamp (indexed) |

## Runner Methods

| Method | Parameters | Returns |
|--------|-----------|---------|
| `record` | All schema fields as kwargs | Record hash (also inserted to DB) |
| `worker_costs` | `worker_id:`, `period: 'daily'` | Aggregated token/call/latency metrics |
| `team_costs` | `team:`, `period: 'daily'` | Team-wide aggregation across all team workers |
| `routing_stats` | `worker_id: nil` | Breakdowns by routing_reason, provider, model, avg latency |
| `cleanup_old_records` | `retention_days: 90` | Deletes records older than cutoff; returns `{ purged:, retention_days:, cutoff: }` |

`period` values: `'daily'`, `'weekly'`, `'monthly'`

## Cleanup Actor

`Actor::Cleanup` is an Every actor that calls `cleanup_old_records` once per day (86,400s). It runs with `run_now? false`, `use_runner? false`, `check_subtask? false`, `generate_task? false` — a minimal background trigger that delegates directly to the runner method.

## Integration Points

- **legion-data**: `data_required? false` — loads without DB. `record` returns hash only (for RabbitMQ publishing). Query methods (`worker_costs`, `team_costs`, `routing_stats`, `cleanup_old_records`) still access `metering_records` as a raw Sequel dataset when `Legion::Data` is available.
- **LegionIO MCP**: `legion.routing_stats` MCP tool calls `routing_stats` runner
- **REST API**: `GET /api/tasks/:id` includes a `:metering` block when lex-metering data exists for the task
- **Digital Workers**: `legion worker costs` CLI command delegates to `worker_costs` runner

## Development Notes

- Extension has `data_required? false` — loads without `legion-data`; `record` builds hash only (no DB insert), query methods still require `Legion::Data`
- Has one explicit actor (`Cleanup`); auto-generated subscription actors are created for runner methods
- `routing_stats` uses `select_append { avg(latency_ms).as(avg_latency) }` — Sequel virtual row syntax
- Time interval filtering uses `Sequel.lit('recorded_at >= ?', cutoff)` with Ruby `Time` arithmetic for cross-database compatibility (PostgreSQL, SQLite, MySQL)
