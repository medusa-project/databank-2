# Illinois Data Bank integration with Medusa Collection Registry

Illinois Data Bank registers datafile binaries in Medusa Collection Registry for digital preservation.

Illinois Data Bank datafiles are copied to storage managed by Medusa Collection Registry.

reference: https://www.library.illinois.edu/digital-strategies/medusa-digital-preservation-repository/

## Architecture Overview

Medusa integration in `databank-2` has two related parts:

- storage roots (where files live and are referenced), and
- ingest event delivery/response tracking (publish notifications to Medusa and response reconciliation).

## Storage Roots and File Location Metadata

Storage roots are defined with `medusa-storage.yml` (demo/production) or `medusa-storage-ci.yml` (development/test).

The initializer selects config by environment:

- `demo` / `production`: `config/medusa-storage.yml`
- non-prod/test-like: `config/medusa-storage-ci.yml`

At runtime, `StorageManager` exposes named roots:

- `draft`
- `medusa`
- `globus_download`
- `globus_ingest`
- `message`
- `reports`
- `tmpfs`

Datafile location is tracked by:

- `datafiles.storage_root`
- `datafiles.storage_key`
- `datafiles.medusa_id` (optional Medusa object identifier)

`Datafile::Storable` resolves the effective root via `StorageManager.instance.root_set.at(storage_root)` and performs `exist?` / streaming IO operations against that root.

Typical flow:

1. Upload API writes depositor uploads to the `draft` root.
2. Medusa ingest pipeline processes published datasets.
3. Responses can include Medusa keys/UUIDs; app stores those in delivery attempt response fields.
4. Download service can use `storage_key` metadata for Medusa-backed files.

## Configuration

### Storage root configuration

Common storage variables used by root configs:

- `STORAGE_S3_REGION`
- `STORAGE_DRAFT_BUCKET`
- `STORAGE_DRAFT_PREFIX`
- `STORAGE_MEDUSA_BUCKET`
- `STORAGE_MEDUSA_PREFIX`
- `STORAGE_GLOBUS_BUCKET`
- `STORAGE_GLOBUS_DOWNLOAD_PREFIX`
- `STORAGE_TMPFS_PATH`

Local/CI MinIO configuration also uses:

- `STORAGE_S3_ENDPOINT`
- `STORAGE_S3_ACCESS_KEY_ID`
- `STORAGE_S3_SECRET_ACCESS_KEY`

In `demo`/`production`, credentials are preferred for most storage and AWS values, with environment fallback.

### Ingest event/response configuration

`IdbConfig.ingest` controls event publishing and response consumption:

- `ENABLE_INGEST_EVENTS`
- `RABBITMQ_URL`
- `INGEST_EVENTS_EXCHANGE` (default `databank.ingest`)
- `INGEST_EVENTS_ROUTING_KEY` (default `dataset.published`)
- `ENABLE_INGEST_RESPONSES`
- `INGEST_RESPONSES_QUEUE` (default `medusa_to_databank`)
- `INGEST_RESPONSE_BATCH_SIZE`
- `INGEST_HEALTH_RESPONSE_STALE_MINUTES`
- `INGEST_HEALTH_ORPHAN_LOOKBACK_MINUTES`
- `INGEST_HEALTH_ORPHAN_ALERT_THRESHOLD`
- `ENABLE_INGEST_HEALTH_ALERTS`
- `INGEST_HEALTH_ALERT_EMAILS`
- `INGEST_HEALTH_ALERT_COOLDOWN_MINUTES`

Downloader integration (for assembled downloads) uses:

- `DOWNLOADER_ENDPOINT`
- `DOWNLOADER_USER`
- `DOWNLOADER_PASSWORD`

## MedusaIngest Parity in databank-2

Legacy app stored Medusa ingest records in `MedusaIngest` rows.

In `databank-2`, functional parity is represented by:

- `ExternalDeliveryAttempt` (event delivery lifecycle and ingest response fields), and
- `IngestResponseEvent` (raw queue response event log: matched/unmatched/invalid).

Legacy migration support:

- `migration:medusa_ingests:import_from_dir` converts legacy `MedusaIngest` bundle records into `ExternalDeliveryAttempt` rows.
- run type is recorded as `medusa_ingests_bundle_import`.

## Publish and Response Flow

### Outbound publish event

On dataset publish:

1. `DatasetsController#publish` marks dataset as published.
2. `Ingest::PublishDatasetEventJob` is enqueued.
3. Job creates `ExternalDeliveryAttempt` with integration `ingest`, event `dataset.published`, status `started`.
4. `Ingest::RabbitmqEventPublisher` publishes event payload to RabbitMQ topic exchange.
5. Attempt is marked `succeeded`, `failed`, or `skipped` (`integration_disabled` / `already_succeeded`).

Published event payload includes dataset identifiers and correlation context (`correlation_key`, `dataset.id`, `dataset.key`, `dataset.identifier`).

### Inbound Medusa response processing

`Ingest::ProcessResponseQueueJob` consumes response messages via `Ingest::RabbitmqResponseConsumer`.

For each message:

1. Correlation key is extracted.
2. Matching `ExternalDeliveryAttempt` is located (or treated as unmatched).
3. Attempt response fields are updated (`response_status`, `response_received_at`, `response_uuid`, `response_target_key`, payload).
4. `IngestResponseEvent` is recorded with status `matched`, `unmatched`, or `invalid`.

Failure responses set attempt status to `failed` and attach a Medusa response error class/message.

## Operations and Monitoring

Admin UI and replay support:

- `GET /admin/external_delivery_attempts`
- replay one failed attempt
- replay selected failed attempts

Ingest replay enqueues `Ingest::PublishDatasetEventJob` with original idempotency key.

Health and alerting:

- Health summary logic checks response freshness/orphans.
- recurring jobs include response queue processing and health alert dispatch.

Cutover/migration orchestration includes a Medusa ingest import step in `cutover:import_all`.

## Troubleshooting

Common checks:

1. Verify storage roots resolve (`draft`, `medusa`, etc.) for current environment.
2. Confirm `RABBITMQ_URL` and ingest enable flags are set as intended.
3. Confirm response queue name matches producer integration.
4. Inspect `ExternalDeliveryAttempt` and `IngestResponseEvent` for correlation and response payload details.
5. Use replay actions for failed ingest attempts after correcting integration issues.

Common failure modes:

- ingest events disabled: attempts marked `skipped` with `integration_disabled`.
- missing/invalid RabbitMQ config: publisher/consumer unavailable.
- unmatched response correlation keys: events recorded as `unmatched`.
- Medusa response indicates error: attempts transition to `failed` with error details.

