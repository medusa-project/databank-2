# Curator Hold Parity: legacy databank vs databank-2

Short answer: curator hold is **largely implemented for curator-facing control flow** in databank-2, including DOI/Globus suppression side-effect handling and draft/version override controls.

databank-2 now has hold-state constants, hold-aware public visibility enforcement, and legacy-style suppression control endpoints and UI.

## What legacy databank implemented

Legacy defined explicit suppression/hold states and workflows:

1. Temporary file suppression
2. Temporary metadata suppression
3. Unsuppress
4. Permanent file suppression
5. Permanent metadata suppression (tombstone behavior)
6. Version-candidate hold (`version candidate under curator review`)

Authoritative state constants are defined in [config/application.rb](../../databank/config/application.rb#L8):

1. `Databank::PublicationState::TempSuppress::{NONE, FILE, METADATA, VERSION}`
2. `Databank::PublicationState::PermSuppress::{FILE, METADATA}`

Legacy controller actions that apply these states are in [app/controllers/datasets_controller.rb](../../databank/app/controllers/datasets_controller.rb#L509), including DOI/Globus side effects for some transitions.

Legacy access enforcement depends on hold state in permissions and model-level visibility logic:

1. [app/models/ability.rb](../../databank/app/models/ability.rb#L44)
2. [app/models/dataset.rb](../../databank/app/models/dataset.rb#L190)

## Current databank-2 status

Implemented:

1. `datasets.hold_state` and `datasets.tombstone_date` fields exist (schema migrated).
2. Migration/import preserves incoming `hold_state` and `tombstone_date`.
3. Canonical hold-state constants are defined in `Dataset` (legacy-compatible string values).
4. Public visibility logic is hold-aware:

- `Dataset.publicly_readable_now` excludes metadata-suppressing and version-review hold states.
- `Dataset.files_publicly_readable_now_scope` excludes file/metadata/version suppressing hold states.
- `Dataset#publicly_readable_now?` and `Dataset#files_publicly_readable_now?` enforce the same at instance level.

5. Search-result badge can label some records as "suppressed by curator".
6. Curator suppression controls are implemented with legacy-matching action names and routing:

- `suppression_controls`
- `suppression_action`
- `suppress_changelog`
- `unsuppress_changelog`
- `temporarily_suppress_files`
- `temporarily_suppress_metadata`
- `unsuppress`
- `permanently_suppress_files`
- `permanently_suppress_metadata`
- `suppress_review`
- `unsuppress_review`

7. Suppression Controls page is available from dataset curator controls and uses legacy button labels/branching based on dataset visibility.
8. Legacy-style suppression side-effect handling is wired:

- temporary metadata suppression attempts DataCite hide and shows legacy fallback message on failure
- unsuppress attempts DataCite republish/update and shows legacy fallback message on failure
- permanent file suppression attempts Globus public-copy removal and shows legacy fallback message on failure
- permanent metadata suppression attempts both DataCite + Globus side effects and shows combined failure alert on failure

9. Added model/request spec coverage for hold-aware visibility behavior and suppression fallback messages.
10. Legacy-style draft/version override controls are implemented:

- `draft_to_version`
- `version_to_draft`
- version-draft publish guard requiring pre-publication review until toggled back.

References:

1. [db/schema.rb](db/schema.rb#L236)
2. [app/services/migration/dataset_upsert_service.rb](app/services/migration/dataset_upsert_service.rb#L98)
3. [app/services/migration/flat_bundle_import_service.rb](app/services/migration/flat_bundle_import_service.rb#L446)
4. [app/models/dataset.rb](app/models/dataset.rb#L58)
5. [app/models/dataset.rb](app/models/dataset.rb#L95)
6. [app/models/dataset.rb](app/models/dataset.rb#L319)
7. [config/routes.rb](config/routes.rb#L28)
8. [app/controllers/datasets_controller.rb](app/controllers/datasets_controller.rb#L183)
9. [app/views/datasets/suppression_controls.html.haml](app/views/datasets/suppression_controls.html.haml#L1)
10. [app/views/datasets/show.html.haml](app/views/datasets/show.html.haml#L299)
11. [app/views/datasets/version_controls.html.haml](app/views/datasets/version_controls.html.haml#L171)
12. [db/migrate/20260806120000_add_suppress_changelog_to_datasets.rb](db/migrate/20260806120000_add_suppress_changelog_to_datasets.rb#L1)
13. [app/services/doi/suppression_service.rb](app/services/doi/suppression_service.rb#L1)
14. [app/services/globus/suppression_service.rb](app/services/globus/suppression_service.rb#L1)
15. [app/services/doi/datacite_client.rb](app/services/doi/datacite_client.rb#L31)
16. [spec/models/dataset_embargo_spec.rb](spec/models/dataset_embargo_spec.rb#L112)
17. [spec/requests/embargo_access_spec.rb](spec/requests/embargo_access_spec.rb#L239)
18. [spec/requests/curator_suppression_controls_spec.rb](spec/requests/curator_suppression_controls_spec.rb#L1)
19. [app/helpers/datasets_helper.rb](app/helpers/datasets_helper.rb#L91)
20. [app/views/datasets/index/\_result_badges.html.haml](app/views/datasets/index/_result_badges.html.haml#L31)
21. [app/controllers/datasets_controller.rb](app/controllers/datasets_controller.rb#L302)
22. [config/routes.rb](config/routes.rb#L42)
23. [app/views/datasets/version_controls.html.haml](app/views/datasets/version_controls.html.haml#L184)

Not implemented (functional gaps):

1. Legacy publication-state string transitions for permanent suppression are not replicated because databank-2 uses enum `publication_state` (`draft`/`published`) instead of legacy multi-string publication states.
2. Legacy `publication_state == version` semantics are represented via `hold_state == version candidate under curator review` on draft datasets.

Evidence:

1. databank-2 now has suppression endpoints and DOI/Globus suppression-side-effect services.
2. databank-2 publication_state remains enum-based, so legacy string-valued permanent suppression publication_state cannot be mirrored 1:1.

## Conclusion

Curator hold concept is now **functional for curator UI controls and hold-state enforcement** in databank-2.

Full legacy parity still requires publication-state override semantics if those are required.

## Recommended implementation sequence

1. Validate with curators whether any additional UI wording/placement differences remain in Version Controls.
2. Add any additional message-parity refinements requested by curators after UAT.

## Suggested acceptance criteria

1. A metadata-suppressed dataset is not publicly readable before unsuppress/release path.
2. A file-suppressed dataset keeps metadata visible but blocks public file access.
3. Permanent suppression sets tombstone behavior and executes required downstream side effects.
4. Version hold state follows legacy behavior for version-review visibility and acknowledgements.
5. Search/listing facets and badges accurately reflect effective hold state.
