# Dataset publication_state values

Current application values for `Dataset.publication_state` are defined by enum in [app/models/dataset.rb](app/models/dataset.rb#L93).

## Canonical values

1. `draft`

- Stored integer: `0`
- Meaning: dataset is not published.
- Default value for new records.
- Draft records are not included in public-read scopes.

2. `published`

- Stored integer: `1`
- Meaning: dataset is in published state.
- Visibility still depends on embargo/release-date logic (metadata/files may still be delayed).

## Important distinction

`publication_state` has only two values (`draft`, `published`).

User-facing labels such as:

- "Metadata Published, Files Publication Delayed (Embargoed)"
- "Metadata and Files Publication Delayed (Embargoed)"

come from embargo/release-date logic, not additional `publication_state` enum values. See [app/models/dataset.rb](app/models/dataset.rb#L260).

## Legacy import mapping

During migration/import, several legacy state strings are normalized into the two canonical enum values in [app/services/migration/dataset_upsert_service.rb](app/services/migration/dataset_upsert_service.rb#L4).

Legacy states mapped to `draft`:

- `draft`
- `version candidate under curator review`

Legacy states mapped to `published`:

- `released`
- `published`
- `file embargo`
- `metadata embargo`
- `files temporarily suppressed`
- `metadata temporarily suppressed`
- `files permanently suppressed`
- `metadata permanently suppressed`

The flat-bundle importer also normalizes `released` to `published`; unknown values are ignored there. See [app/services/migration/flat_bundle_import_service.rb](app/services/migration/flat_bundle_import_service.rb#L748).
