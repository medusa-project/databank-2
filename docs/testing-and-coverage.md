# Testing and coverage

This document describes local test execution and current coverage policy guidance for databank-2.

## Test suite

This project uses RSpec.

Run the full test suite:

```sh
bundle exec rspec
```

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
