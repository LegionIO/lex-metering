# lex-metering: LLM Cost Metering for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-core/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Captures LLM token usage metrics per task for cost attribution and intelligent routing. Records input/output/thinking tokens, latency, wall-clock time, CPU time, external API call counts, and routing reason per metered call. Supports per-worker, per-team, and aggregate routing statistics queries.

## Gem Info

- **Gem name**: `lex-metering`
- **Version**: `0.1.0`
- **Module**: `Legion::Extensions::Metering`
- **Ruby**: `>= 3.4`
- **License**: MIT
- **GitHub**: https://github.com/LegionIO/lex-metering
- **Note**: No `.git` directory yet (created 2026-03-13, not yet pushed to GitHub)

## File Structure

```
lib/legion/extensions/metering/
  version.rb
  data/
    migrations/
      001_add_metering_records.rb  # Creates metering_records table
  runners/
    metering.rb   # record, worker_costs, team_costs, routing_stats
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

`period` values: `'daily'`, `'weekly'`, `'monthly'`

## Integration Points

- **legion-data**: `data_required? true` — will not load if DB unavailable. Accesses `metering_records` as a raw Sequel dataset (no Sequel::Model subclass).
- **LegionIO MCP**: `legion.routing_stats` MCP tool calls `routing_stats` runner
- **REST API**: `GET /api/tasks/:id` includes a `:metering` block when lex-metering data exists for the task
- **Digital Workers**: `legion worker costs` CLI command delegates to `worker_costs` runner

## Development Notes

- Extension has `data_required? true` (both at module level and instance level) — will skip loading if `legion-data` is not connected
- No explicit actors — gets auto-generated subscription actors from the framework
- `routing_stats` uses `select_append { avg(latency_ms).as(avg_latency) }` — Sequel virtual row syntax
- Time interval filtering uses `Sequel.lit("CURRENT_TIMESTAMP - INTERVAL '...'")` which is PostgreSQL syntax; SQLite uses different interval syntax (known limitation)
