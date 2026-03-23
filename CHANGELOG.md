# Changelog

## [0.1.8] - 2026-03-22

### Changed
- Migrated gemspec runtime dependency from `legionio` monolith to individual sub-gems: `legion-cache >= 1.3.11`, `legion-crypt >= 1.4.9`, `legion-data >= 1.4.17`, `legion-json >= 1.2.1`, `legion-logging >= 1.3.2`, `legion-settings >= 1.3.14`, `legion-transport >= 1.3.9`
- Updated spec_helper to require real sub-gem helpers; added `Helpers::Lex` stub and `Actors::Every` base class stub

## [0.1.7] - 2026-03-22

### Changed
- Updated `legionio` dependency constraint to `>= 1.4.123`

## [0.1.6] - 2026-03-21

### Added
- `Runners::CostOptimizer` module with `analyze_costs` method for weekly LLM cost analysis
- `Actor::CostOptimizer` periodic actor (runs weekly) to trigger cost analysis
- Cost rate tables for Anthropic, OpenAI, Bedrock, and Azure AI models
- LLM-powered recommendation generation for model rightsizing

## [0.1.5] - 2026-03-20

### Added
- `Helpers::Economics` module with `payroll_summary`, `worker_report`, and `budget_forecast` methods for labor economics reporting

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
