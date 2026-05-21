# README

This README would normally document whatever steps are necessary to get the
application up and running.

## Optional DataCite DOI Integration

Dataset publish uses a fallback DOI generator by default. To enable live
DataCite registration, set these environment variables:

- `DATACITE_API_BASE_URL` (for example, `https://api.test.datacite.org`)
- `DATACITE_USERNAME`
- `DATACITE_PASSWORD`
- `APP_URL` (public base URL of this app)

If `DATACITE_STRICT=true`, publish raises on DataCite failures instead of
falling back to generated DOI values.

## Optional Shibboleth Header Callback

The route `/auth/shibboleth/callback` supports reverse-proxy header mode for
Shibboleth deployments. If OmniAuth auth hash is not present for this provider,
the callback reads identity headers:

- `HTTP_EPPN` or `REMOTE_USER` or `HTTP_UID` (required)
- `HTTP_MAIL` (optional; falls back to uid)
- `HTTP_DISPLAYNAME` or `HTTP_CN` (optional)

This allows stage/production integration behind SSO middleware while keeping
developer provider auth for local development.

## Optional Solr Indexing Sync

Dataset create/update/destroy operations enqueue search indexing jobs when
`SOLR_URL` is present.

- If `SOLR_URL` points to a core/collection base, indexing uses `.../update`.
- If `SOLR_URL` points to `.../select`, indexing automatically rewrites to
	`.../update`.

The indexer posts JSON update payloads and fails safely (logs warning,
application request still succeeds) if Solr is temporarily unavailable.

Nested metadata edits (creators, contributors, funders, related materials)
also enqueue dataset reindex jobs so Solr stays consistent with deposit edits.

To enqueue a full backfill:

```sh
bin/rails search:reindex_all
```

## Testing

This project uses RSpec.

Run the full test suite:

```sh
bundle exec rspec
```

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
