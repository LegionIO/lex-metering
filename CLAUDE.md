# lex-metering

LLM cost metering for LegionIO. Records token usage per task for cost attribution and intelligent routing: input/output/thinking tokens, latency, wall-clock time, CPU time, external API calls, cost in USD, trace context, and routing reason. Supports per-worker, per-team, and aggregate queries. Hourly rollup to summary table.

## Architecture

```
Legion::Extensions::Metering
├── Runners/
│   ├── Metering         # record, worker_costs, team_costs, routing_stats, cleanup_old_records
│   ├── CostOptimizer    # analyze_costs (LLM-powered model rightsizing recommendations)
│   └── Rollup           # rollup_hour, purge_raw_records
├── Actors/
│   ├── Cleanup(86400s)       # Daily: cleanup_old_records; use_runner? false
│   ├── CostOptimizer(604800s) # Weekly: analyze_costs; Singleton mixin
│   └── Rollup(3600s)         # Hourly: rollup_hour; run_now? false
└── Data/Migrations/     # 001_add_metering_records, 002_add_trace_columns, 003_add_metering_indexes
```

## Key Design Decisions

- **`data_required? true`**: migrations auto-run on boot. `record` returns hash for RMQ publishing; query methods require `Legion::Data`.
- **Rollup**: groups by worker/provider/model per hour into `metering_hourly_rollup` (upsert semantics). `purge_raw_records(retention_days: 7)` cleans rolled-up data.
- **CostOptimizer**: weekly LLM-powered analysis with built-in rate table (Opus $15, Sonnet $3, Haiku $0.25, GPT-4o $5, etc. per 1M tokens). Uses `caller: { extension: 'lex-metering', operation: 'cost_optimization' }`.
- **Period values**: `'daily'`, `'weekly'`, `'monthly'` for worker_costs/team_costs.
- **routing_stats**: uses `select { [provider, avg(latency_ms).as(avg_latency)] }` Sequel virtual row syntax with explicit projection.
- Actor module is singular (`module Actor`) per framework convention.
- Integration: MCP tool `legion.routing_stats`, REST API includes `:metering` block, CLI `legion worker costs`, shared `metering_records` table with lex-llm-gateway.
