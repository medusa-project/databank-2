# Illinois Data Bank databank-2

## Project Overview

databank-2 is the Rails application for Illinois Data Bank dataset management and publication workflows, including authentication, metadata publishing, and preservation storage integrations.

## Quick Start

1. Install dependencies and initialize local app state:

```sh
bin/setup
```

2. Start local development services:

```sh
bin/dev
```

3. Run the test suite:

```sh
bundle exec rspec
```

## Common Commands

- CI parity checks:

```sh
bin/ci
```

- Ruby lint:

```sh
bin/rubocop -f github
```

- Security scans:

```sh
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
```

## Repository Map

- App code: app/
- Framework and runtime config: config/
- Tests/specs: spec/, test/
- Build and developer scripts: bin/, script/
- Operational and integration docs: docs/

## Integration Documentation

Developer-facing integration configuration and operational details are documented in `docs/`:

- [Shibboleth integration](docs/shibboleth-integration.md)
- [Illinois Experts integration](docs/illinois-experts-integration.md)
- [DataCite integration](docs/datacite-integration.md)
- [Medusa integration](docs/medusa-integration.md)
- [Ingest events integration](docs/ingest-events-integration.md)
- [External delivery audit](docs/external-delivery-audit.md)
- [Globus integration](docs/globus-integration.md)

## Migration Pipelines (Initial Implementation)

Migration runbooks, import/export commands, and binary storage migration notes are documented in:

- [Migration pipelines](docs/migration-pipelines.md)
- [Medusa integration](docs/medusa-integration.md)

## Testing

Testing and coverage guidance is documented in:

- [Testing and coverage](docs/testing-and-coverage.md)


## Pre-Push Checklist

Pre-push checks are documented in:

- [Local pre-push checklist](docs/local-pre-push-checklist.md)

## Demo-First Capistrano Deploy Runbook

Deployment runbook details are documented in:

- [Demo-first deploy runbook](docs/demo-first-deploy-runbook.md)
- [Deploy config contract](docs/deploy-config-contract.md)

## Troubleshooting Links

- Deployment and config contract checks: [Deploy config contract](docs/deploy-config-contract.md)
- Local quality gates before push: [Local pre-push checklist](docs/local-pre-push-checklist.md)
- Testing and coverage expectations: [Testing and coverage](docs/testing-and-coverage.md)
- Migration and cutover imports: [Migration pipelines](docs/migration-pipelines.md)
- Integration-specific behavior and config: see the links under Integration Documentation
