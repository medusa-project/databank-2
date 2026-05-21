# README

This README would normally document whatever steps are necessary to get the
application up and running.

## Optional DataCite DOI Integration

Dataset publish uses a fallback DOI generator by default. To enable live
DataCite registration, set these environment variables:

- `DATACITE_API_BASE_URL` (for example, `https://api.test.datacite.org`)
- `DATACITE_USERNAME`
- `DATACITE_PASSWORD`
- `APP_URL` (public base URL of this app)

If `DATACITE_STRICT=true`, publish raises on DataCite failures instead of
falling back to generated DOI values.

## Optional Shibboleth Header Callback

The route `/auth/shibboleth/callback` supports reverse-proxy header mode for
Shibboleth deployments. If OmniAuth auth hash is not present for this provider,
the callback reads identity headers:

- `HTTP_EPPN` or `REMOTE_USER` or `HTTP_UID` (required)
- `HTTP_MAIL` (optional; falls back to uid)
- `HTTP_DISPLAYNAME` or `HTTP_CN` (optional)

This allows stage/production integration behind SSO middleware while keeping
developer provider auth for local development.

## Optional Solr Indexing Sync

Dataset create/update/destroy operations enqueue search indexing jobs when
`SOLR_URL` is present.

- If `SOLR_URL` points to a core/collection base, indexing uses `.../update`.
- If `SOLR_URL` points to `.../select`, indexing automatically rewrites to
	`.../update`.

The indexer posts JSON update payloads and fails safely (logs warning,
application request still succeeds) if Solr is temporarily unavailable.

Nested metadata edits (creators, contributors, funders, related materials)
also enqueue dataset reindex jobs so Solr stays consistent with deposit edits.

To enqueue a full backfill:

```sh
bin/rails search:reindex_all
```

## Optional Ingest Event Publishing (RabbitMQ / Medusa Scaffold)

On successful dataset publish, the app enqueues an ingest event job.

Set these variables to enable RabbitMQ publish:

- `ENABLE_INGEST_EVENTS=true`
- `RABBITMQ_URL` (for example, `amqp://guest:guest@rabbitmq:5672`)
- `INGEST_EVENTS_EXCHANGE` (optional, default `databank.ingest`)
- `INGEST_EVENTS_ROUTING_KEY` (optional, default `dataset.published`)

If not enabled or if publish to RabbitMQ fails, the app logs a warning and
continues serving the user request.

## Optional Globus Transfer Submission

On successful dataset publish, the app also enqueues a Globus transfer job.

Set these variables to enable transfer submission:

- `ENABLE_GLOBUS_TRANSFER=true`
- `GLOBUS_TRANSFER_ENDPOINT` (for example, `https://globus.example.org/api/transfers`)
- `GLOBUS_TRANSFER_TOKEN` (bearer token)
- `GLOBUS_SOURCE_COLLECTION`
- `GLOBUS_DESTINATION_COLLECTION`
- `GLOBUS_SOURCE_BASE_PATH` (optional, default `/`)
- `GLOBUS_DESTINATION_BASE_PATH` (optional, default `/`)

If Globus transfer is not enabled or submission fails, the app logs a warning
and keeps the user publish flow successful.

## External Delivery Audit Trail

Each ingest and globus background delivery attempt is persisted in
`external_delivery_attempts` with:

- integration (`ingest` or `globus`)
- event name (`dataset.published`)
- status (`started`, `skipped`, `succeeded`, `failed`)
- attempt number and job id
- optional failure details (`error_class`, `error_message`, `details`)

Delivery jobs use an idempotency key (`dataset.published:<dataset_id>:<published_at>`) and
skip external submission when a prior `succeeded` attempt exists for the same
dataset/integration/event key.

Admins can replay failed delivery attempts for a dataset via:

- `POST /datasets/:id/replay_failed_deliveries`
- optional `integration` param: `ingest`, `globus`, or `all` (default)

Replay enqueues one job per failed integration/idempotency key pair.

Admins can browse delivery attempts at:

- `GET /admin/external_delivery_attempts`

Supported filters: `dataset_key`, `integration`, `status`, `event_name`.

The audit page also supports CSV export with active filters/sort:

- `GET /admin/external_delivery_attempts.csv`

This provides an operational record for diagnosing delivery and replay flows.

## Testing

This project uses RSpec.

Run the full test suite:

```sh
bundle exec rspec
```

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
