# Illinois Data Bank integration with Globus

[Globus](https://www.globus.org/what-we-do) is a nonprofit platform created by the University of Chicago and Argonne National Laboratory that enables the transfer of digital files between established endpoints, one of which can be your work or personal computer. Globus also offers additional services related to sharing data with other researchers or parties directly.

In this application, Globus is used in two distinct flows:

1. Internal ingest flow: operators import files already placed into the configured ingest root and create `Datafile` records in the application.
2. Public download flow: operators copy publicly readable dataset files into a configured download root so users can retrieve them through Globus.

Both flows follow the Illinois Data Bank directory convention:

- `<dataset_key>/<filename>`

Example:

- `IDB-1234567/analysis.csv`

## Dataset page workflows

The legacy Globus workflows are available through the dataset record:

- Public datasets with `all_globus` set have an **Open in Globus** link in the Files
  section, including datasets with just one file. The route checks public file
  visibility and Globus readiness before redirecting; private links and curator
  access do not bypass embargoes or suppression for public Globus downloads.
- Opening Globus records downloads for the dataset's files using the same daily
  IP-based deduplication as browser downloads. This counts opening File Manager,
  not confirmation of a completed Globus transfer, matching legacy behavior.
- Curators editing a dataset can use **Open Globus Ingest Folder** (when configured)
  and **Import from Globus**. Import is a POST, skips existing filenames, and
  reports failures and partial imports explicitly. As in the legacy app, curators
  can also import into published records. New imports clear `all_globus` and
  `all_medusa` until all files are copied/preserved again.
- Newly created datasets get an ingest directory when `ingest_url_base` is
  configured. Existing dataset directories can be prepared with
  `dataset.ensure_globus_ingest_dir` from the Rails console.
- Dataset destruction cleans configured ingest/download directories before
  destroying associated records. Cleanup failures prevent record destruction.
  Ingest files referenced by another dataset version are not deleted.
- The `Dataset::Globusable` concern also provides the legacy copy, single-file
  deletion, ingest import, and directory-removal methods for operator use.

### File Manager configuration

Configure these independently of the optional Transfer API:

| IDB config / credentials key | Environment fallback | Purpose |
| --- | --- | --- |
| `globus.download_url_base` | `GLOBUS_DOWNLOAD_URL_BASE` | Public collection File Manager URL |
| `globus.ingest_url_base` | `GLOBUS_INGEST_URL_BASE` | Ingest collection File Manager URL; enables directory provisioning |
| `globus.only_gb` | `GLOBUS_ONLY_GB` (default `2`) | Size threshold, in GiB, for the pending-Globus notice |

Example URL bases (replace collection IDs and paths for each environment):

```text
https://app.globus.org/file-manager?origin_id=DOWNLOAD_COLLECTION_ID&origin_path=%2F
https://app.globus.org/file-manager?origin_id=INGEST_COLLECTION_ID&origin_path=%2Fdatabank%2Fingest%2F
```

Copy the appropriate `download_url_base` and `ingest_url_base` from the legacy
environment's Globus configuration into these new keys. No collection IDs or
deployment paths are assumed. URL bases must use HTTPS and include `origin_id`
and an absolute `origin_path`; dataset keys are appended to that path with
proper query encoding. A missing or invalid download URL gives an explicit
configuration error rather than redirecting somewhere arbitrary.

The public collection must expose only the configured `globus_download` root.
The ingest collection must be private and mapped to `globus_ingest`. App-level
authorization cannot revoke access to a public Globus collection itself.
Permanent suppression removes public copies; temporary holds hide the app's
link but do not change collection-level ACLs or remove existing public copies.

## Upload

To set up your systems to use Globus to transfer files to your computer, refer to the getting started guide from Globus for detailed guidance on setting up and account and installing Globus Connect Personal.

Once you configure and select an endpoint to send the files to (on your personal computer or other system) you can click on the "Open in Globus File Manager" button on a dataset download page.

### Transfer API configuration

Outgoing transfer submission is handled by `Globus::TransferService` and `Globus::SubmitDatasetTransferJob`.

Configure these keys in `idb_config.yml` (typically via credentials or environment fallback):

- `globus.transfer_enabled`
- `globus.transfer_endpoint`
- `globus.transfer_token`
- `globus.source_collection`
- `globus.destination_collection`
- `globus.source_base_path`
- `globus.destination_base_path`

Environment variable names for those keys:

- `ENABLE_GLOBUS_TRANSFER`
- `GLOBUS_TRANSFER_ENDPOINT`
- `GLOBUS_TRANSFER_TOKEN`
- `GLOBUS_SOURCE_COLLECTION`
- `GLOBUS_DESTINATION_COLLECTION`
- `GLOBUS_SOURCE_BASE_PATH`
- `GLOBUS_DESTINATION_BASE_PATH`

When enabled, dataset file transfer payload paths are generated as:

- source: `<source_base_path>/<dataset_key>/<binary_name>`
- destination: `<destination_base_path>/<dataset_key>/<binary_name>`

Publish-flow behavior:

- transfer submission is enqueued after successful publish,
- if transfer is disabled, submission is skipped,
- if submission fails, a warning is logged and publish remains successful.

## Download

The datasets in Illinois Data Bank's repository hold files of varying sizes. While files can be downloaded directly from datasets through a browser, Globus can offer a faster alternative that can be especially noticeable on datasets larger than a few Gigabytes.

## Storage root configuration

Globus integration uses Medusa storage roots. Ensure these roots exist and point to the intended buckets/prefixes in `config/medusa-storage.yml` (and CI equivalents):

- `globus_ingest`: source location for files uploaded through mediated Globus ingest.
- `globus_download`: destination location for public-copy files for end-user download.
- `draft`: storage root referenced by imported `Datafile` records.

In standard deployments, `globus_ingest` and `draft` can refer to compatible locations where imported datafiles are stored and served.

## Rake tasks

### Import datafiles from Globus ingest

Task:

- `bundle exec rake globus:import_datafiles_from_ingest`

Optional environment variables:

- `DATASET_KEY=IDB-1234567` to scope to one dataset.
- `DRY_RUN=true` to preview without creating records.
- `DATASET_LIMIT=50` to stop after scanning N datasets.

Behavior:

- Scans dataset directories at `<dataset_key>/` in `globus_ingest`.
- For each file key under that directory, derives `binary_name` from `File.basename(storage_key)`.
- Creates `Datafile` records with:
	- `storage_root = draft`
	- `storage_key = <dataset_key>/<filename>`
	- `binary_size = size in globus_ingest`
- Idempotent by `dataset + binary_name`: existing file names are skipped.
- When `globus_ingest` and `draft` have different storage configurations, copies
  files into `draft` before creating their records. Matching roots share files
  without copying. S3 prefixes containing files do not require a directory marker.

### Copy public datafiles to Globus download root

Task:

- `bundle exec rake globus:copy_public_datafiles`

Optional environment variables:

- `DATASET_KEY=IDB-1234567` to scope to one dataset.
- `DRY_RUN=true` to preview without copying.
- `DATASET_LIMIT=50` to stop after scanning N datasets.

Behavior:

- Processes datasets where `files_publicly_readable_now?` is true.
- Builds destination keys as `<dataset_key>/<binary_name>`.
- Copies from each datafile's current storage root/key to `globus_download`.
- Idempotent: skips records where destination key already exists.
- Reconciles `all_globus` against the presence of every file, clearing stale
  flags as well as setting them.
- `bundle exec rake globus:copy_datasets` remains available as a legacy alias.

## Operational notes

- Run tasks with `DRY_RUN=true` before production runs.
- Use `DATASET_KEY` for controlled re-runs and incident response.
- Task output includes a JSON summary of scanned, copied/created, skipped, and failed counts.
- Failures are logged and processing continues for remaining records.

## Troubleshooting

- No records imported:
	- Verify `globus_ingest` is configured and contains `<dataset_key>/` directories.
	- Confirm dataset keys in storage exactly match application dataset keys.
- Copies skipped unexpectedly:
	- Check dataset publication and embargo state (`files_publicly_readable_now?`).
	- Verify destination keys do not already exist in `globus_download`.
- Missing file sizes or copy errors:
	- Validate Medusa root credentials and bucket/prefix access.
	- Confirm source `storage_root` and `storage_key` on `Datafile` records are valid.
