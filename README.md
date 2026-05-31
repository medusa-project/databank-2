# README

## Optional DataCite DOI Integration

Dataset publish uses a fallback DOI generator by default. To enable live
DataCite registration, set these environment variables:

- `DATACITE_API_BASE_URL` (for example, `https://api.test.datacite.org`)
- `DATACITE_USERNAME`
- `DATACITE_PASSWORD`
- `APP_URL` (public base URL of this app)

If `DATACITE_STRICT=true`, publish raises on DataCite failures instead of
falling back to generated DOI values.

## Shibboleth Header Callback

The route `/auth/shibboleth/callback` supports reverse-proxy header mode for
Shibboleth deployments. If OmniAuth auth hash is not present for this provider,
the callback reads identity headers:

- `HTTP_EPPN` or `REMOTE_USER` or `HTTP_UID` (required)
- `HTTP_MAIL` (optional; falls back to uid)
- `HTTP_DISPLAYNAME` or `HTTP_CN` (optional)

This allows stage/production integration behind SSO middleware while keeping
developer provider auth for local development.

## Ingest Event Publishing (RabbitMQ / Medusa Scaffold)

On successful dataset publish, the app enqueues an ingest event job.

Set these variables to enable RabbitMQ publish:

- `ENABLE_INGEST_EVENTS=true`
- `RABBITMQ_URL` (for example, `amqp://guest:guest@rabbitmq:5672`)
- `INGEST_EVENTS_EXCHANGE` (optional, default `databank.ingest`)
- `INGEST_EVENTS_ROUTING_KEY` (optional, default `dataset.published`)

If not enabled or if publish to RabbitMQ fails, the app logs a warning and
continues serving the user request.

## Globus Transfer Submission

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
- `POST /admin/external_delivery_attempts/:id/replay` (replay one failed attempt)
- `POST /admin/external_delivery_attempts/replay_selected` (replay selected failed attempts)

Supported filters: `dataset_key`, `integration`, `status`, `event_name`.

The audit page also supports CSV export with active filters/sort:

- `GET /admin/external_delivery_attempts.csv`

This provides an operational record for diagnosing delivery and replay flows.

## Migration Pipelines (Initial Implementation)

## Binary Storage Strategy (Medusa Storage)

databank-2 now supports legacy-compatible binary metadata handling using
`medusa_storage` roots. For metadata migration, binaries are not copied or
rewritten. Existing `datafiles.storage_root` and `datafiles.storage_key` values
are preserved and used for download access.

Implementation notes:

- `Datafile` keeps storage metadata fields (`storage_root`, `storage_key`, `medusa_id`).
- Download flow checks, in order:
	- Active Storage attachment (if present), then
	- Medusa root/key location, then
	- placeholder fallback.
- Migration import preserves `storage_root` and `storage_key` exactly from source
	payloads so existing binaries remain addressable in place.

Storage configuration files:

- `config/medusa-storage-ci.yml` (development/test)
- `config/medusa-storage.yml` (production)

Set S3/MinIO environment values (`STORAGE_*`) to match legacy bucket/prefix
layout before running storage-backed downloads.

Two migration flows are now available:

- sample flow for development-safe data using public JSON endpoints
- bundle flow for secure legacy exports that include depositor fields

### 1) Sample Fetch (Public URLs -> Local Snapshot)

Fetch payloads listed in `working/datasets.json` into a timestamped run folder
under `working/migration_samples`.

```sh
bin/rails migration:sample:fetch
```

Optional params:

- `LIST=/custom/path/datasets.json`
- `OUTPUT_ROOT=/custom/output/root`
- `LIMIT=25`

Output includes:

- `datasets/*.json` raw payload snapshots
- `summary.json` fetch report

### 2) Sample Import (Snapshot -> databank-2)

Import one fetch run directory into databank-2 with idempotent defaults.

```sh
bin/rails migration:sample:import INPUT_DIR=working/migration_samples/<run_timestamp>
```

Behavior:

- default: skip existing datasets
- `OVERWRITE=true`: update existing datasets and refresh nested metadata
- `DRY_RUN=true`: no writes; reports what would change

Sample import uses fallback depositor fields unless set:

- `MIGRATION_SAMPLE_OWNER_UID` (default `legacy-import`)
- `MIGRATION_SAMPLE_DEPOSITOR_NAME` (default `Legacy Import`)
- `MIGRATION_SAMPLE_DEPOSITOR_EMAIL` (default `legacy-import@example.edu`)

### 3) Secure Bundle Import (Legacy Export -> databank-2)

Import NDJSON bundles exported from legacy databank. Each record must include:

- `owner_uid`
- `depositor_name`
- `depositor_email`

```sh
bin/rails migration:bundle:import BUNDLE=/path/to/legacy_export.ndjson
```

Optional params:

- `OVERWRITE=true`
- `DRY_RUN=true`
- `CHECKSUM=/path/to/legacy_export.ndjson.sha256`
- `MANIFEST=/path/to/manifest.json`

This is the target import path for production migration runs where sensitive
depositor/owner fields are sourced from legacy systems.

If `CHECKSUM` or `MANIFEST` is provided, the importer verifies SHA256 integrity
before writing any records. If `MANIFEST` includes `record_count`, that value is
also validated against processed NDJSON rows.

### 4) Production Export -> Secure Copy -> Local Import

You can run export on production (legacy app), copy the bundle locally, then run
import in local databank-2.

Legacy production export (run on legacy host):

```sh
bin/rails migration:legacy:export_bundle OUTPUT_ROOT=/tmp/databank_migration_exports SINCE=2026-01-01T00:00:00Z
```

Secure copy to local machine (example):

```sh
scp -r user@legacy-host:/tmp/databank_migration_exports/20260521T000000Z ./working/legacy_exports/
```

Local databank-2 import from copied files:

```sh
bin/rails migration:bundle:import \
	BUNDLE=working/legacy_exports/20260521T000000Z/legacy_datasets.ndjson \
	CHECKSUM=working/legacy_exports/20260521T000000Z/legacy_datasets.ndjson.sha256 \
	MANIFEST=working/legacy_exports/20260521T000000Z/manifest.json \
	DRY_RUN=true
```

Then execute without `DRY_RUN=true` after validation.

Convenience command for copied export directories:

```sh
bin/rails migration:bundle:import_from_dir DIR=working/legacy_exports/20260521T000000Z DRY_RUN=true
```

Defaults used by `import_from_dir`:

- bundle: `legacy_datasets.ndjson`
- checksum: `legacy_datasets.ndjson.sha256` (if present)
- manifest: `manifest.json` (if present)

Optional overrides:

- `BUNDLE_FILE=custom.ndjson`
- `CHECKSUM_FILE=custom.ndjson.sha256`
- `MANIFEST_FILE=custom_manifest.json`
- or absolute file paths via `CHECKSUM=/abs/path` and `MANIFEST=/abs/path`

## Testing

This project uses RSpec.

Run the full test suite:

```sh
bundle exec rspec
```

### Coverage Baseline and Rationale

This project now uses SimpleCov and generates coverage output in `coverage/`.

Current baseline (full `bundle exec rspec` run):

- line coverage: `84.6%` (`2252 / 2662`)

Why coverage can reasonably be below 80% in the short term:

- several integration-heavy surfaces are intentionally thin wrappers around external systems (for example DataCite and migration pipelines)
- some controller/UI flows currently rely on request-level rendering assertions where broad branch coverage is expensive and brittle
- migration/import code paths include operational guard rails that are hard to fully simulate in unit tests without over-mocking

Coverage policy for this repo:

- treat `80%` as a medium-term target, not an immediate hard gate
- each feature branch should add tests for meaningful behavior changes, especially service logic and permission rules
- prioritize low-covered core code with operational risk (migration services, auth/access control, publish/version workflows) before chasing cosmetic line gains


## Pre-Commit Checklist

Use this checklist before pushing a branch. It is ordered from fastest checks
to slower checks.

### 1) CI parity checks (required)

These are the checks that map directly to GitHub Actions and should pass before
you push.

1. Ruby lint

```sh
bin/rubocop -f github
```

Why: mirrors the `lint` job in CI.

2. Rails security scan

```sh
bin/brakeman --no-pager
```

Why: mirrors the `scan_ruby` Brakeman step in CI.

3. Gem vulnerability audit

```sh
bin/bundler-audit
```

Why: mirrors the `scan_ruby` gem audit step in CI.

4. JavaScript dependency audit

```sh
bin/importmap audit
```

Why: mirrors the `scan_js` job in CI.

Tip: run all CI parity checks via one command:

```sh
bin/ci
```

### 2) Local-only quality checks (recommended)

These are not currently required by GitHub Actions, but they are strongly
recommended before opening or updating a PR.

1. Full backend test suite (RSpec)

```sh
bundle exec rspec
```

Why: catches behavior regressions CI may not catch if tests are not part of the
workflow.

2. End-to-end browser tests (Playwright)

```sh
npm run test:e2e
```

Why: validates key user flows in a real browser locally.

3. Accessibility scan (axe + Playwright)

```sh
npm run test:e2e:a11y
```

Why: catches accessibility issues earlier and supports WCAG-focused work.

### 3) Final sanity checks

1. Confirm branch and staged changes

```sh
git status --short
git branch --show-current
```

2. Push only after all required checks pass locally.
