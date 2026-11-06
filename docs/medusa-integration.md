# Illinois Data Bank integration with Medusa Collection Registry

Illinois Data Bank registers datafile binaries in Medusa Collection Registry for digital preservation.

Illinois Data Bank datafiles are copied to storage managed by Medusa Collection Registry.

reference: https://www.library.illinois.edu/digital-strategies/medusa-digital-preservation-repository/

## Architecture Overview

Medusa integration in `databank-2` has two related parts:

- storage roots (where files live and are referenced), and
- per-file ingest request delivery/response tracking.

Related docs:

- event publish/consume flow: [Ingest events integration](ingest-events-integration.md)
- delivery attempt lifecycle and replay operations: [External delivery audit](external-delivery-audit.md)

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

The `medusa_storage` dependency uses its `databank` branch, with `io-like`
restricted to 0.3.x because the storage gem requires the module-based
`IO::Like` API. Version 0.4 changes it to a class and prevents boot.
JSON is restricted to version 2 because Rails 8.1's JSON decoder passes
arguments that JSON 3 no longer accepts.

Typical flow:

1. The token-authenticated Tus API writes chunks as S3 multipart uploads in
   the `draft` root and keeps resumable metadata in S3. Registration references
   the completed object directly; it does not download or copy the file locally.
   The maximum Tus upload is 50 GiB. Each PATCH is limited to 64 MiB, and
   non-final chunks must be at least 5 MiB or large enough to keep the total
   part count under 10,000. Use the bundled Python client for compatible chunk
   sizing. Proxy and application servers may buffer a PATCH body locally, so
   size temporary storage for concurrent chunks rather than entire files.
   Interrupted multipart uploads and unregistered completed uploads remain in
   S3; configure an S3 lifecycle rule to abort incomplete multipart uploads and
   use an operational cleanup process that checks dataset references before
   deleting completed objects. Deploying this change does not migrate uploads
   staged by the former local Tus implementation; finish them before deployment
   or restart them afterward.
2. Browser uploads initially use Active Storage. Before ingest, they are streamed into the MedusaStorage `draft` root and their location metadata is updated.
3. Publishing sends one Medusa `operation: ingest` request per file, using the prefixed draft storage key and `dataset.key/binary_name` as the preservation target. Medusa's IDB staging root must point to the matching bucket/key namespace.
4. Responses can include Medusa keys/UUIDs; app stores those in per-file delivery attempt response fields.
5. Finalization promotes available preserved files to the MedusaStorage `medusa` root and removes matching draft copies. The existing Active Storage attachment is retained.
6. Download service can use `storage_key` metadata for Medusa-backed files.

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

## Event and delivery operations

Event publishing/consumption and delivery replay are documented in dedicated files:

- [Ingest events integration](ingest-events-integration.md)
- [External delivery audit](external-delivery-audit.md)

Cutover/migration orchestration still includes a Medusa ingest import step in `cutover:import_all`.

## Troubleshooting

Common checks:

1. Verify storage roots resolve (`draft`, `medusa`, etc.) for current environment.
2. Confirm ingest event settings and response queue configuration via [Ingest events integration](ingest-events-integration.md).
3. Inspect `ExternalDeliveryAttempt` and `IngestResponseEvent` for correlation and response payload details.
4. Use replay actions described in [External delivery audit](external-delivery-audit.md).

Common failure modes:

- ingest events disabled: attempts marked `skipped` with `integration_disabled`.
- missing/invalid RabbitMQ config: publisher/consumer unavailable.
- unmatched response correlation keys: events recorded as `unmatched`.
- Medusa response indicates error: attempts transition to `failed` with error details.
