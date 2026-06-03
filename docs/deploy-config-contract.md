# Deploy Config Contract

This document defines where deploy-time configuration lives and how to verify it.

## Goal

- Keep secrets encrypted.
- Keep non-secret, environment-specific values explicit and discoverable.
- Fail fast before deploy if required values are missing.

## Source Of Truth By Value Type

1. Secrets (tokens, passwords, private keys): Rails credentials per environment.
2. Non-secret, environment-specific constants (URLs, bucket names, prefixes):
   Prefer committed per-environment config in `config/idb_config.yml` and `config/medusa-storage.yml` with credentials fallback where needed.
3. Runtime host/process toggles (log level, one-off flags): environment variables.

## Current Contract (Deployed Environments)

The following must resolve to non-blank values for `demo` and `production`:

1. Core app config
- `IDB_CONFIG.app.url`
- `IDB_CONFIG.app.root_url_text`
- `IDB_CONFIG.mail.from`

2. Storage root set (`STORAGE_CONFIG[:storage]`)
- Required roots: `draft`, `medusa`, `globus_download`, `globus_ingest`, `message`, `reports`, `tmpfs`
- For S3 roots: `region`, `bucket`
- For filesystem roots: `path`

3. Feature-conditional requirements
- If `IDB_CONFIG.doi.strict` is true: `doi.api_base_url`, `doi.username`, `doi.password`
- If `IDB_CONFIG.ingest.events_enabled` is true: `ingest.rabbitmq_url`, `ingest.events_exchange`, `ingest.events_routing_key`
- If `IDB_CONFIG.globus.transfer_enabled` is true: `globus.transfer_endpoint`, `globus.transfer_token`, `globus.source_collection`, `globus.destination_collection`

4. Active Storage (`amazon`)
- If Active Storage service resolves to `amazon`, `config/storage.yml` must provide non-blank `amazon.region` and `amazon.bucket`
- Blank `amazon.access_key_id` and `amazon.secret_access_key` are acceptable only when IAM role/profile auth is used

## Verification Commands

Local verification for a target environment:

```sh
RAILS_ENV=demo bundle exec rake config:contract
RAILS_ENV=production bundle exec rake config:contract
RAILS_ENV=demo bundle exec rake config:contract_report
RAILS_ENV=production bundle exec rake config:contract_report
```

During deploy, this runs automatically before asset precompile via Capistrano task `deploy:config_contract`.

Use [docs/credentials-template.yml](docs/credentials-template.yml) as the expected
key layout when editing per-environment credentials.

Use [docs/config-source-matrix.md](docs/config-source-matrix.md) for the
environment-by-environment source map (credentials vs env vs defaults).

## Recommended Practice

1. Keep secrets in credentials.
2. Keep non-secret environment constants in committed config files when stable.
3. Use environment variables for host-level runtime overrides and operational toggles.
4. Keep defaults in one place; avoid requiring the same value from both credentials and env unless one is an intentional fallback.
5. Treat `config:contract` as a release gate.