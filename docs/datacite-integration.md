# Illinois Data Bank integration with DataCite

Illinois Data Bank registers DOIs with DataCite, providing metadata to support finding datasets and associated resources.

Illinois Data Bank has a dedicated prefix range, and manages DOIs within that range.

## Configuration

DataCite settings are loaded through `IdbConfig` under the `doi` key.

Environment variables:

- `DATACITE_API_BASE_URL`
- `DATACITE_USERNAME`
- `DATACITE_PASSWORD`
- `DATACITE_STRICT` (`true` or `false`, default `false`)

Environment-specific behavior in this app:

- `development` / `test`: values come from environment variables.
- `demo` / `production`: credentials are preferred, with environment variable fallback.

Credentials keys used in `demo` and `production`:

- `datacite.api_base_url` (or `datacite.endpoint` as fallback)
- `datacite.username`
- `datacite.password`
- `datacite.strict`

Related application URL setting:

- `app.url` (used to build the dataset URL sent to DataCite)

## Usage in the Publish Flow

DOI minting and DataCite registration happen during dataset publish.

Implementation path:

- `DatasetsController#publish` calls `Doi::IdentifierService#mint_for_publish!`.
- If the dataset already has an identifier, that identifier is reused.
- If no identifier exists, a DOI is generated using `Dataset#generate_doi`.
- DataCite registration is attempted only when all three values are present:
	- `doi.api_base_url`
	- `doi.username`
	- `doi.password`

If DataCite is not configured:

- publish continues,
- generated DOI is used locally,
- no registration request is sent.

If DataCite is configured and registration fails:

- with `doi.strict=true`: publish raises and fails.
- with `doi.strict=false`: warning is logged, publish continues with generated DOI.

Note on draft workflow:

- `DatasetsController#request_review` may set an identifier for drafts when blank.
- DataCite registration still occurs only in `publish`, not in `request_review`.

## DataCite Request Payload

The app sends a JSON:API request to:

- `POST {doi.api_base_url}/dois`

Headers:

- `Content-Type: application/vnd.api+json`
- Basic auth using `doi.username` and `doi.password`

Payload fields currently sent:

- `doi`: generated or existing DOI
- `event`: `publish`
- `url`: `{app.url}/datasets/{dataset.key}`
- `titles[0].title`: dataset title
- `publisher`: dataset publisher, defaulting to `Illinois Data Bank`
- `publicationYear`: dataset published year (or current year if not yet set)
- `types.resourceTypeGeneral`: `Dataset`

## Operational Notes

- Registration is synchronous in the web request path for publish.
- A successful publish also queues ingest and Globus jobs, but DOI registration is handled before those jobs are queued.
- Response status outside 2xx from DataCite is treated as a failure.

## Verification and Troubleshooting

Quick checks:

1. Confirm config is present in the target environment (`doi.api_base_url`, `doi.username`, `doi.password`).
2. Confirm `app.url` points to the externally reachable dataset URL base.
3. Publish a dataset and verify:
	 - identifier assigned in app,
	 - expected strict/non-strict behavior on DataCite errors.

Common failure modes:

- Missing DataCite credentials: registration skipped.
- Incorrect API base URL: request failures or 404/401 responses.
- Invalid credentials: 401/403 from DataCite.
- Strict mode enabled with DataCite outage: publish fails fast.

