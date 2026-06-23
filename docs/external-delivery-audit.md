# Illinois Data Bank external delivery audit and replay

Illinois Data Bank tracks external integration deliveries in `external_delivery_attempts` and supports operational replay through dataset and admin endpoints.

This document covers audit data model semantics, replay behavior, and admin operations.

## Delivery attempt model

Each attempt records:

- `integration` (`ingest` or `globus`)
- `event_name` (`dataset.published`)
- `status` (`started`, `skipped`, `succeeded`, `failed`)
- attempt number
- job id
- optional failure details (`error_class`, `error_message`, `details`)

Delivery jobs use an idempotency key format:

- `dataset.published:<dataset_id>:<published_at>`

When a prior successful attempt exists for the same dataset/integration/event/idempotency key, repeat delivery is skipped.

## Replay behavior

Replay enqueues one job per failed integration/idempotency-key pair.

Ingest replay enqueues `Ingest::PublishDatasetEventJob` with the original idempotency context.

## Dataset replay API

- `POST /datasets/:id/replay_failed_deliveries`
- optional `integration` param:
  - `ingest`
  - `globus`
  - `all` (default)

## Admin audit UI and endpoints

Browse attempts:

- `GET /admin/external_delivery_attempts`

Replay endpoints:

- `POST /admin/external_delivery_attempts/:id/replay`
- `POST /admin/external_delivery_attempts/replay_selected`

Supported filters:

- `dataset_key`
- `integration`
- `status`
- `event_name`

CSV export:

- `GET /admin/external_delivery_attempts.csv`

## Operational checks

1. Validate integration-level enable flags and endpoint credentials.
2. Confirm failed attempts have actionable error fields.
3. Resolve config/network/integration issues before replaying.
4. Re-run replay and verify transition from `failed` to `succeeded` or `skipped`.
