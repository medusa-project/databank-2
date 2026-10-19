# Testing and coverage

This document describes local test execution and current coverage policy guidance for databank-2.

## Test suite

This project uses RSpec.

Run the full test suite:

```sh
bundle exec rspec
```

### Datafile request coverage

```sh
RAILS_ENV=test bundle exec rspec spec/requests/datafiles_spec.rb
```

These specs cover single and bulk file operations, partial upload failures,
dataset-scoped removal, authorization boundaries, and cached/attachment/storage
preview behavior. MedusaStorage roots are mocked for storage-backed previews;
no live storage access is required. Assertions check response bodies, metadata,
counts, inline MIME types, and preview sanitization rather than status alone.
Unused archive-tree helpers are not exercised solely to increase coverage.

### Dataset edit accessibility

```sh
PW_SKIP_GLOBAL_SETUP=1 npx playwright test playwright/deposit-form.spec.js
```

These browser tests create their own datasets, so they do not need the migration
fixture imports in global setup. They verify native labels for individual and
organization creators in initial and dynamically added rows, keyboard focus when
adding/reordering/removing creators, ORCID dialog focus restoration, the file
chooser button, independent access-grant and file-deletion forms, and mobile
metadata layout.
Axe scans cover the main edit content, including expanded curator sections.
Automated checks supplement, rather than replace, manual screen-reader, zoom,
and keyboard testing for WCAG 2.2 AA.

### Private sharing

```sh
bundle exec rspec spec/models/share_code_spec.rb spec/models/dataset/sharable_spec.rb spec/requests/dataset_sharing_spec.rb
PW_SKIP_GLOBAL_SETUP=1 npx playwright test playwright/share-code.spec.js
```

These specs cover random-code collisions, one-year expiry, publication and embargo
release, authenticated link management, dataset-scoped guest reads and downloads,
preview navigation, aggregate downloads, and effective-code badges independent of
upload tokens. The browser test checks native labeled controls, keyboard activation,
clipboard feedback, guest access, revocation, and WCAG 2.2 AA rules with axe.

### Metric export coverage

```sh
RAILS_ENV=test bundle exec rspec spec/models/metric_spec.rb
```

Metric specs run the actual TSV/CSV writers and verify exact headers, rows,
aggregates, CSV quoting, relationship expansion, and public visibility filtering.
Calendar/fiscal download exports test inclusive year boundaries and file-access
restrictions. Failure tests verify that locks are cleared, archival removes local
files only after a successful storage copy, and failed copies preserve local data.
ZIP tests verify entry names and contents.

Export files and year-specific files under `public/` are redirected to a temporary
directory for these model specs. MedusaStorage report roots are mocked, so the
tests do not overwrite real exports or access live archive storage.

### Configuration contract task coverage

```sh
RAILS_ENV=test bundle exec rspec spec/tasks/config_contract_tasks_spec.rb
```

These tests invoke `config:contract` and `config:contract_report` with isolated
configuration and credentials. They verify required storage roots, enabled
integration requirements, aggregated failure messages and exit status, Amazon
Active Storage requirements/IAM warnings, and source precedence without revealing
secret values. Environment presence checks and storage YAML reads are mocked;
no deployed credentials, environment variables, or storage services are changed.

## Coverage baseline and rationale

This project uses SimpleCov and generates coverage output in `coverage/`.

Current baseline (full `bundle exec rspec` run):

- line coverage: `84.6%` (`2252 / 2662`)

Why coverage can reasonably be below 80% in the short term:

- several integration-heavy surfaces are intentionally thin wrappers around external systems (for example DataCite and migration pipelines)
- some controller/UI flows currently rely on request-level rendering assertions where broad branch coverage is expensive and brittle
- migration/import code paths include operational guard rails that are hard to fully simulate in unit tests without over-mocking

## Coverage policy

- treat `80%` as a medium-term target, not an immediate hard gate
- each feature branch should add tests for meaningful behavior changes, especially service logic and permission rules
- prioritize low-covered core code with operational risk (migration services, auth/access control, publish/version workflows) before chasing cosmetic line gains
