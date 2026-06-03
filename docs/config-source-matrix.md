# Environment Config Source Matrix

This matrix summarizes where deployed runtime values should come from.

## Source Types

- committed-config: checked-in config files under `config/`
- credentials: Rails encrypted credentials for the target environment
- env: process or host environment variables
- default: hard-coded fallback in config templates

## Matrix

| Area | Key | dev/test | demo/production preferred | Allowed fallback | Secret? |
| --- | --- | --- | --- | --- | --- |
| app | `IDB_CONFIG.app.url` | committed-config or env | credentials | env, default | no |
| app | `IDB_CONFIG.app.root_url_text` | committed-config or env | credentials | env, default | no |
| app | `IDB_CONFIG.mail.from` | committed-config or env | credentials | env, default | no |
| storage root-set | `storage.region` | env/default | credentials (`aws.region`) | env/default | no |
| storage root-set | `storage.draft_bucket` | env/default | credentials (`storage.draft_bucket`) | env | no |
| storage root-set | `storage.medusa_bucket` | env/default | credentials (`storage.medusa_bucket`) | env | no |
| storage root-set | `storage.globus_bucket` | env/default | credentials (`storage.globus_bucket`) | env | no |
| storage root-set | `storage.draft_prefix` | env/default | credentials (`storage.draft_prefix`) | env/default | no |
| storage root-set | `storage.medusa_prefix` | env/default | credentials (`storage.medusa_prefix`) | env/default | no |
| storage root-set | `storage.globus_download_prefix` | env/default | credentials (`storage.globus_download_prefix`) | env/default | no |
| storage root-set | `storage.tmpfs.path` | env/default | env | default | no |
| active storage | `amazon.region` | env | credentials (`aws.region`) | env | no |
| active storage | `amazon.bucket` | env | credentials (`storage.active_storage_bucket`) | credentials (`storage.draft_bucket`), env | no |
| active storage | `amazon.access_key_id` | env | credentials (`aws.access_key_id`) when static creds are used | env or blank with IAM role | yes |
| active storage | `amazon.secret_access_key` | env | credentials (`aws.secret_access_key`) when static creds are used | env or blank with IAM role | yes |
| DataCite | `doi.api_base_url` | env/default | credentials | env/default | no |
| DataCite | `doi.username` | env | credentials | env | yes |
| DataCite | `doi.password` | env | credentials | env | yes |
| Globus | `globus.transfer_endpoint` | env | credentials | env | no |
| Globus | `globus.transfer_token` | env | credentials | env | yes |
| Ingest | `ingest.rabbitmq_url` | env | credentials | env | often yes |
| downloader | `downloader.endpoint` | env | credentials | env | no |
| downloader | `downloader.user` | env | credentials | env | yes |
| downloader | `downloader.password` | env | credentials | env | yes |

## Verification Workflow

1. Run source report for target environment:
   - `RAILS_ENV=demo bundle exec rake config:contract_report`
   - `RAILS_ENV=production bundle exec rake config:contract_report`
2. Run contract gate:
   - `RAILS_ENV=demo bundle exec rake config:contract`
   - `RAILS_ENV=production bundle exec rake config:contract`

## Notes

- For demo and production, prefer credentials for stable environment-specific constants unless there is a strong operational need to override via env.
- Use env for host-level overrides such as logging level and one-off feature toggles.
- If using IAM role/profile auth for S3, blank access key and secret key are expected.