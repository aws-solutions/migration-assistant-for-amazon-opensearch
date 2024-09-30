# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [2.0.0] - 2024-09-30

### Added
 - Support for workloads up to 100TB with the new Reindex-from-Snapshot capability
 - Added Migration Console CLI to facilitate migrations
 - GovCloud support
 - Backfill Pause-and-Resume, with the ability to roll back a migration
 - Increased vertical performance on Replay
 - Metadata Migration Tool to migrate cluster settings and configurations
 - Load balancer configuration to facilitate zero-downtime migrations
 - Support for new migration paths, including 6.x, 7.x, and 1.x as source versions
 - Support for multi-hop migrations

### Removed
 - Fetch Backfill support

## [1.0.0] - 2023-11-17

### Added

- All files, initial release

