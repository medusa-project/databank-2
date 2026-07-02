# Migration pipelines

This document covers migration workflows and storage handling used by databank-2 during legacy cutover and import runs.

## Binary storage strategy (Medusa Storage)

databank-2 supports legacy-compatible binary metadata handling using `medusa_storage` roots. For metadata migration, binaries are not copied or rewritten. Existing `datafiles.storage_root` and `datafiles.storage_key` values are preserved and used for download access.

Implementation notes:

- `Datafile` keeps storage metadata fields (`storage_root`, `storage_key`, `medusa_id`).
- Download flow checks, in order:
  - Active Storage attachment (if present), then
  - Medusa root/key location, then
  - placeholder fallback.
- Migration import preserves `storage_root` and `storage_key` exactly from source payloads so existing binaries remain addressable in place.

Storage configuration files:

- `config/medusa-storage-ci.yml` (development/test)
- `config/medusa-storage.yml` (production)

Set S3/MinIO environment values (`STORAGE_*`) to match legacy bucket/prefix layout before running storage-backed downloads.

Two migration flows are available:

- sample flow for development-safe data using public JSON endpoints
- bundle flow for secure legacy exports that include depositor fields

## 1) Sample fetch (public URLs to local snapshot)

Fetch payloads listed in `working/datasets.json` into a timestamped run folder under `working/migration_samples`.

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

## 2) Sample import (snapshot to databank-2)

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

## 3) Secure flat bundle import (legacy export to databank-2)

Import NDJSON bundles exported from legacy databank. Each record must include:

- `owner_uid`
- `depositor_name`
- `depositor_email`

```sh
bin/rails migration:flat_bundle:import_from_dir DIR=/path/to/export_dir
```

Optional params:

- `OVERWRITE=true`
- `DRY_RUN=true`
- `BUNDLE_FILE=legacy_datasets.ndjson`
- `CHECKSUM_FILE=legacy_datasets.ndjson.sha256`
- `MANIFEST_FILE=manifest.json`
- `CHECKSUM=/abs/path/to/legacy_datasets.ndjson.sha256`
- `MANIFEST=/abs/path/to/manifest.json`

This is the target import path for production migration runs where sensitive depositor/owner fields are sourced from legacy systems.
The flat format uses one NDJSON stream with entity records (`dataset`, `datafile`, `nested_item`) and is imported in streaming batches.

If `CHECKSUM` or `MANIFEST` is provided, the importer verifies SHA256 integrity before writing any records.

## 4) Production export to secure copy to local import (sequential repo workflow)

Run export on production (legacy app), copy the bundle locally, then run import in local databank-2.
Operate one repo at a time: complete export in legacy, then switch to databank-2 for import.

Legacy production export (run on legacy host):

```sh
bin/rails migration:legacy:export_bundle OUTPUT_ROOT=/tmp/databank_migration_exports SINCE=2026-01-01T00:00:00Z
```

To intentionally include legacy test datasets in a production migration export:

```sh
INCLUDE_TESTS=true \
bin/rails migration:legacy:export_bundle OUTPUT_ROOT=/tmp/databank_migration_exports
```

Test datasets are imported into databank-2 with `is_test=true`. In databank-2,
test datasets are excluded from public readability and public dataset listings,
while remaining available for curator/internal testing workflows.

Secure copy to local machine (example):

```sh
scp -r user@legacy-host:/tmp/databank_migration_exports/20260521T000000Z ./working/legacy_exports/
```

Local databank-2 import from copied files:

```sh
bin/rails migration:flat_bundle:import_from_dir \
  DIR=working/legacy_exports/20260521T000000Z \
  DRY_RUN=true
```

Then execute without `DRY_RUN=true` after validation.

Convenience command for copied export directories:

```sh
bin/rails migration:flat_bundle:import_from_dir DIR=working/legacy_exports/20260521T000000Z DRY_RUN=true
```

Defaults used by `migration:flat_bundle:import_from_dir`:

- bundle: `legacy_datasets.ndjson`
- checksum: `legacy_datasets.ndjson.sha256` (if present)
- manifest: `manifest.json` (if present)

Optional overrides:

- `BUNDLE_FILE=custom.ndjson`
- `CHECKSUM_FILE=custom.ndjson.sha256`
- `MANIFEST_FILE=custom_manifest.json`
- or absolute file paths via `CHECKSUM=/abs/path` and `MANIFEST=/abs/path`
