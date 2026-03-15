# lex-metering

Captures LLM token usage, latency, and routing metrics per task for cost attribution and intelligent routing decisions.

**Ruby >= 3.4** | **License**: MIT | **Author**: [@Esity](https://github.com/Esity)

## Purpose

`lex-metering` records every LLM call made through a Legion digital worker — tokens consumed, latency, wall-clock time, CPU time, external API calls, and routing reason. Data is persisted to the `metering_records` table and queried for cost attribution and routing statistics.

## Installation

Included with the LegionIO framework. No separate installation needed.

## Usage

```ruby
# Record an LLM call
Legion::Extensions::Metering::Runners::Metering.record(
  worker_id: 'my-worker',
  task_id:   42,
  provider:  'anthropic',
  model_id:  'claude-opus-4-6',
  input_tokens:  1000,
  output_tokens: 500,
  latency_ms:    1200,
  routing_reason: 'cost_optimization'
)

# Query worker costs
costs = Legion::Extensions::Metering::Runners::Metering.worker_costs(
  worker_id: 'my-worker',
  period:    'daily'
)

# Query routing statistics
stats = Legion::Extensions::Metering::Runners::Metering.routing_stats
```

## Database

Requires `legion-data`. Creates the `metering_records` table via Sequel migration.

## Record Retention

Metering records are pruned automatically by the `Cleanup` actor, which runs once per day. The default retention period is 90 days. Records with a `recorded_at` older than the cutoff are permanently deleted.

To trigger cleanup manually:

```ruby
Legion::Extensions::Metering::Runners::Metering.cleanup_old_records(retention_days: 90)
# => { purged: 1234, retention_days: 90, cutoff: 2025-12-15 00:00:00 UTC }
```

## Related

- [LegionIO](https://github.com/LegionIO/LegionIO) — Framework
- [legion-data](https://github.com/LegionIO/legion-data) — Persistence layer
- [Digital Worker Platform](../../../docs/spec-digital-worker-integration.md) — Cost governance
