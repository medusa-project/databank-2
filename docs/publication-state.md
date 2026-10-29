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

### Controller organization

[DatasetsController::Publishable](../app/controllers/concerns/datasets_controller/publishable.rb)
groups the HTTP actions for pre-publication review requests and confirmation,
and publishing.
[DatasetsController::Holdable](../app/controllers/concerns/datasets_controller/holdable.rb)
groups curator suppression/release controls, including changelog suppression,
the suppression action allowlist, and suppression service helpers.
Dataset lookup and authentication callbacks remain in
[DatasetsController](../app/controllers/datasets_controller.rb).

Version creation and version-request review remain in
[DatasetsController::Versionable](../app/controllers/concerns/datasets_controller/versionable.rb).
External-delivery monitoring and replay remain in the controller. This separation
organizes existing behavior without changing routes, permissions, or responses.

### State and visibility

`publication_state` has only two values (`draft`, `published`).

User-facing labels such as:

- "Metadata Published, Files Publication Delayed (Embargoed)"
- "Metadata and Files Publication Delayed (Embargoed)"

come from embargo/release-date logic, not additional `publication_state` enum values. See [app/models/dataset.rb](app/models/dataset.rb#L260).

### File-section access

The dataset show page uses `can?(:view_files, dataset)` to gate the entire file
listing, including filenames, descriptions, sizes, external-file links, previews,
and download controls. Viewers without file access see a suppression or active
embargo message instead. Authorized owners, editors, curators, and eligible
share-link visitors retain access while temporary holds are in place.

Permanent file suppression preserves owner/editor/curator access, but does not
permit share-link access. Permanent metadata suppression is curator-only:
non-curator permissions are denied even for owners and editors. Share codes are
not accepted for either permanent suppression state. These rules also apply to
file preview/download endpoints, not just their presentation on the show page.
Permanently metadata-suppressed datasets are excluded from non-curator search
results, including owned and explicitly shared datasets.

For suppressed datasets and version-review holds, curators see an informational
box at the top of the Metadata section explaining the restriction and their
continued curator access. The notice does not hide metadata or change permissions,
and is not shown to other viewers or for datasets without a hold.

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
