# Illinois Data Bank ingest events integration (RabbitMQ / Medusa)

Illinois Data Bank publishes dataset ingest events to RabbitMQ and consumes Medusa response messages for correlation and status updates.

This document covers event publishing and response processing behavior.

For storage root and file-location metadata details, see [Medusa integration](medusa-integration.md).
For delivery attempt and replay/audit operations, see [External delivery audit](external-delivery-audit.md).

## Configuration

`IdbConfig.ingest` controls event publishing and response consumption.

Environment variables:

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

## Publish event flow

On dataset publish:

1. `DatasetsController#publish` marks the dataset as published.
2. `Ingest::PublishDatasetEventJob` is enqueued.
3. The job creates an `ExternalDeliveryAttempt` (`integration=ingest`, `event_name=dataset.published`, `status=started`).
4. `Ingest::RabbitmqEventPublisher` publishes the event payload to RabbitMQ.
5. Delivery attempt status transitions to `succeeded`, `failed`, or `skipped`.

If event publishing is disabled or publish-to-RabbitMQ fails, the app logs a warning and keeps the user publish flow successful.

## Response queue flow

`Ingest::ProcessResponseQueueJob` consumes Medusa response messages via `Ingest::RabbitmqResponseConsumer`.

For each message:

1. Correlation key is extracted.
2. Matching `ExternalDeliveryAttempt` is resolved.
3. Response fields are persisted on the attempt (`response_status`, `response_received_at`, `response_uuid`, `response_target_key`, payload).
4. `IngestResponseEvent` is recorded with status `matched`, `unmatched`, or `invalid`.

Failure responses transition the attempt to `failed` and persist error details.

## Operations and monitoring

- Recurring jobs process response queues and evaluate ingest health.
- Health summary logic checks stale responses and orphaned response events.
- Alert dispatch behavior is controlled by ingest health settings.

## Troubleshooting

1. Confirm `ENABLE_INGEST_EVENTS` and `ENABLE_INGEST_RESPONSES` are set as intended.
2. Confirm `RABBITMQ_URL`, exchange, routing key, and queue are correct.
3. Check `IngestResponseEvent` for unmatched or invalid events.
4. Check `ExternalDeliveryAttempt` response fields for correlation and error context.
