# Changelog

## [0.1.4] - 2026-03-18

### Changed
- `record` no longer writes directly to database; returns hash only for RabbitMQ publishing
- `data_required?` changed to `false` — extension loads without legion-data

## [0.1.3] - 2026-03-18

### Fixed
- `worker_costs` period filtering now uses cross-DB `Sequel.lit('recorded_at >= ?', cutoff)` with Ruby time arithmetic instead of PostgreSQL-only `CURRENT_TIMESTAMP - INTERVAL` syntax

## [0.1.2] - 2026-03-17

### Changed
- Renamed `module Actors` to `module Actor` (singular) in `actors/cleanup.rb` to match LegionIO builder convention

## [0.1.1] - 2026-03-15

### Added
- `cleanup_old_records` runner method with configurable retention (default 90 days)
- `Cleanup` periodic actor (runs daily) to prune old metering records

## [0.1.0] - 2026-03-13

### Added
- `record` method for capturing LLM token usage metrics
- `worker_costs` aggregation by worker ID and time period
- `team_costs` aggregation across team members
- `routing_stats` breakdown by routing reason, provider, and model
- Database migration for `metering_records` table
- Full RSpec test coverage for all runner methods
