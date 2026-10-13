# Illinois Data Bank ingest events integration (RabbitMQ / Medusa)

Illinois Data Bank sends per-file ingest requests to Medusa through RabbitMQ and consumes response messages for correlation and status updates.

This document covers event publishing and response processing behavior.

For storage root and file-location metadata details, see [Medusa integration](medusa-integration.md).
For delivery attempt and replay/audit operations, see [External delivery audit](external-delivery-audit.md).

## Configuration

`IdbConfig.ingest` controls event publishing and response consumption.

Environment variables:

- `ENABLE_INGEST_EVENTS`
- `RABBITMQ_URL`
- `INGEST_REQUESTS_QUEUE` (required when ingest is enabled; must match Medusa's incoming queue for client `idb`)
- `ENABLE_INGEST_RESPONSES`
- `INGEST_RESPONSES_QUEUE` (default `medusa_to_databank`)
- `INGEST_RESPONSE_BATCH_SIZE`
- `INGEST_HEALTH_RESPONSE_STALE_MINUTES`
- `INGEST_HEALTH_ORPHAN_LOOKBACK_MINUTES`
- `INGEST_HEALTH_ORPHAN_ALERT_THRESHOLD`
- `ENABLE_INGEST_HEALTH_ALERTS`
- `INGEST_HEALTH_ALERT_EMAILS`
- `INGEST_HEALTH_ALERT_COOLDOWN_MINUTES`

## Publish event flow

On dataset publish:

1. `DatasetsController#publish` marks the dataset as published.
2. `Ingest::PublishDatasetEventJob` is enqueued.
3. Files already stored in Medusa are skipped. Each remaining file gets its own `ExternalDeliveryAttempt` (`integration=ingest`, `event_name=dataset.published`, `status=started`) and correlation key.
4. Active Storage-only browser uploads are streamed into the MedusaStorage `draft` root before sending. Existing draft files are checked for availability.
5. `Ingest::RabbitmqEventPublisher` declares the configured durable request queue and publishes a persistent file-ingest request through RabbitMQ's default exchange.
6. Publisher confirms are required before an attempt transitions to `succeeded`. Staging/publish failures cause retries; already confirmed files are not resent on a retry of the dataset job.

The request follows Medusa's IDB file-ingest protocol:

```json
{
  "operation": "ingest",
  "staging_key": "uploads/source/analysis.csv",
  "target_key": "IDB-1234567/analysis.csv",
  "pass_through": {
    "dataset_id": 1,
    "dataset_key": "IDB-1234567",
    "datafile_id": 2,
    "datafile_web_id": "abc12",
    "correlation_key": "dataset.published:1:2026-10-13T12:00:00Z:datafile:2"
  }
}
```

`staging_key` includes the MedusaStorage draft root prefix. `target_key` is
`dataset.key/binary_name`, matching the finalization service. Medusa's IDB staging
root must read that same draft bucket/key namespace. Duplicate target filenames
within a dataset are rejected before publication.

This replaces the former dataset-level `dataset.published` topic notification.
`INGEST_EVENTS_EXCHANGE` and `INGEST_EVENTS_ROUTING_KEY` are no longer used.
Before enabling the new publisher, configure `INGEST_REQUESTS_QUEUE` (or
`ingest.requests_queue` in deployed credentials). The job/class names and audit
`event_name` remain unchanged for queued-job and replay compatibility.
Legacy successful dataset notifications do not count as file-ingest deliveries.
Delivery remains at-least-once: a lost confirmation can cause a retry even if
Medusa received the first request.

If event publishing is disabled or publish-to-RabbitMQ fails, the app logs a warning and keeps the user publish flow successful.

## Response queue flow

`Ingest::ProcessResponseQueueJob` consumes Medusa response messages via `Ingest::RabbitmqResponseConsumer`.

For each message:

1. Correlation key is extracted.
2. Matching `ExternalDeliveryAttempt` is resolved.
3. Response fields are persisted on the attempt (`response_status`, `response_received_at`, `response_uuid`, `response_target_key`, payload).
4. `IngestResponseEvent` is recorded with status `matched`, `unmatched`, or `invalid`.

Failure responses transition the attempt to `failed` and persist error details.

The current consumer uses manual acknowledgments after payload processing. It
acknowledges matched, unmatched, and invalid messages, including processing
failures returned as `invalid`; it does not requeue or dead-letter those failures.
Queue or acknowledgment errors are logged and reraised, and an open connection
is closed on exit.

## Offline tests

Run the RabbitMQ publisher, response consumer, and their job specs:

```sh
RAILS_ENV=test bundle exec rspec \
  spec/services/ingest/rabbitmq_event_publisher_spec.rb \
  spec/services/ingest/rabbitmq_response_consumer_spec.rb \
  spec/jobs/ingest/publish_dataset_event_job_spec.rb \
  spec/jobs/ingest/process_response_queue_job_spec.rb
```

The service specs replace Bunny connections/channels/queues/exchanges with doubles;
no broker connection is made. Ingest finalization
is also mocked in response consumer specs, avoiding Medusa storage calls.
Coverage includes configuration gates, MedusaStorage staging, persistent ingest payloads, publisher confirms, batch limits,
manual acknowledgments, result counts, and cleanup/error handling.

IDB-specific ingest response tests follow the pinned
[Collection Registry IDB ingest steps](https://github.com/medusa-project/medusa-collection-registry/blob/16085ab66b2b9a71407e90f690fba3a93b9aa7b9/out/test/medusa/step_definitions/idb/ingest_idb_file.rb):
`operation: ingest`, `status: ok`, `staging_key`, and `medusa_key` on success;
`status: error` and an `error` message for duplicate-file failures. Both examples
include echoed `pass_through.correlation_key` supplied by IDB for matching.
The tests assert attempt state, stored response fields/payloads, audit events,
and finalization dispatch on success only.

Generic Medusa response examples additionally exercise `success`/`failure`
status, `message` errors, and nested `pass_through` context, following the
[Collection Registry response base](https://github.com/medusa-project/medusa-collection-registry/blob/main/app/models/amqp_response/base.rb).
These tests verify the file-ingest request shape but do not verify live broker
delivery/redelivery or the deployed Medusa storage/queue configuration.

## Operations and monitoring

- Recurring jobs process response queues and evaluate ingest health.
- Health summary logic checks stale responses and orphaned response events.
- Alert dispatch behavior is controlled by ingest health settings.

## Troubleshooting

1. Confirm `ENABLE_INGEST_EVENTS` and `ENABLE_INGEST_RESPONSES` are set as intended.
2. Confirm `RABBITMQ_URL`, exchange, routing key, and queue are correct.
3. Check `IngestResponseEvent` for unmatched or invalid events.
4. Check `ExternalDeliveryAttempt` response fields for correlation and error context.
