# Embargo in databank-2

This document describes dataset embargo states, how embargo is recorded, and where embargo affects behavior.

## Embargo states

Canonical embargo values are defined in the `Dataset` model:

1. `none`

- No publication delay.
- Metadata and files are public when `publication_state` is `published` (and not test-only).

2. `file`

- File-only publication delay.
- Metadata can be public before `release_date`.
- Files are blocked until `release_date`.

3. `metadata`

- Metadata and file publication delay.
- Neither metadata nor files are public until `release_date`.

Source: `EMBARGO_NONE`, `EMBARGO_FILE`, `EMBARGO_METADATA`, `EMBARGO_OPTIONS` in [app/models/dataset.rb](app/models/dataset.rb#L54).

## How embargo is recorded

Embargo data is persisted on the `datasets` table:

1. `datasets.embargo` (`string`)
2. `datasets.release_date` (`date`)

Source: [db/schema.rb](db/schema.rb#L223).

Related field:

1. `datasets.publication_state` (`integer enum`)

- `draft` or `published`.
- Embargo logic only matters for public access when dataset is `published`.

## Normalization and validation

Runtime model behavior:

1. Blank embargo is normalized to `none` via `normalize_embargo`.
2. `embargo` must be one of `none`, `file`, `metadata`.
3. For published datasets, `release_date` is required when embargo is `file` or `metadata`.

Source: [app/models/dataset.rb](app/models/dataset.rb#L133), [app/models/dataset.rb](app/models/dataset.rb#L442).

Import/migration normalization:

1. `dataset_upsert_service` maps text containing `metadata` to `metadata`, text containing `file` to `file`, else nil.
2. `flat_bundle_import_service` maps:

- blank or `none` -> `none`
- `file` or `file embargo` -> `file`
- `metadata` or `metadata embargo` -> `metadata`

Source: [app/services/migration/dataset_upsert_service.rb](app/services/migration/dataset_upsert_service.rb#L157), [app/services/migration/flat_bundle_import_service.rb](app/services/migration/flat_bundle_import_service.rb#L801).

## How embargo is used at runtime

Model-level predicates:

1. `embargo_mode`
2. `file_embargoed?`
3. `metadata_embargoed?`
4. `embargo_released?`
5. `publicly_readable_now?`
6. `files_publicly_readable_now?`

Source: [app/models/dataset.rb](app/models/dataset.rb#L287).

Query scopes:

1. `Dataset.publicly_readable_now`

- Includes only published, non-test datasets.
- Excludes `metadata` embargo rows until `release_date`.

2. `Dataset.files_publicly_readable_now_scope`

- Includes only published, non-test datasets.
- Excludes `file` and `metadata` embargo rows until `release_date`.

Source: [app/models/dataset.rb](app/models/dataset.rb#L95).

Authorization and access control:

1. Guest read permission for dataset metadata uses `publicly_readable_now?`.
2. Guest file-view permission uses `files_publicly_readable_now?`.
3. Datafile download/view endpoints enforce these permissions.

Source: [app/models/ability.rb](app/models/ability.rb#L12), [app/controllers/datafiles_controller.rb](app/controllers/datafiles_controller.rb#L34).

UI behavior:

1. Edit form stores embargo + release date via dataset core metadata fields.
2. Show page alert displays embargo warnings and release-date messaging.
3. Curator-facing visibility label shows embargo-aware status text.

Source: [app/views/datasets/\_core_metadata_fields.html.haml](app/views/datasets/_core_metadata_fields.html.haml#L36), [app/views/datasets/\_file_restriction_alert.html.haml](app/views/datasets/_file_restriction_alert.html.haml#L1), [app/models/dataset.rb](app/models/dataset.rb#L260).

Downstream usage:

1. Search/list access for guests is based on `Dataset.publicly_readable_now` in dataset listing flow.
2. Metrics/jobs use `Dataset.publicly_readable_now` and `Dataset.files_publicly_readable_now_scope` to limit public reporting/download sets.
3. Globus public-copy checks `files_publicly_readable_now?` before copying files.

Source: [app/controllers/datasets_controller.rb](app/controllers/datasets_controller.rb#L724), [app/models/metric.rb](app/models/metric.rb#L285), [app/services/globus/public_copy_service.rb](app/services/globus/public_copy_service.rb#L43).

## Practical summary

1. `publication_state` controls draft vs published.
2. `embargo` controls what is delayed (`none`, `file`, `metadata`).
3. `release_date` is the date gate that lifts `file` or `metadata` restrictions.
