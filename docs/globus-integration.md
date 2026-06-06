# Illinois Data Bank integration with Globus

[Globus](https://www.globus.org/what-we-do) is a nonprofit platform created by the University of Chicago and Argonne National Laboratory that enables the transfer of digital files between established endpoints, one of which can be your work or personal computer. Globus also offers additional services related to sharing data with other researchers or parties directly.

In this application, Globus is used in two distinct flows:

1. Internal ingest flow: operators import files already placed into the configured ingest root and create `Datafile` records in the application.
2. Public download flow: operators copy publicly readable dataset files into a configured download root so users can retrieve them through Globus.

Both flows follow the Illinois Data Bank directory convention:

- `<dataset_key>/<filename>`

Example:

- `IDB-1234567/analysis.csv`

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

When enabled, dataset file transfer payload paths are generated as:

- source: `<source_base_path>/<dataset_key>/<binary_name>`
- destination: `<destination_base_path>/<dataset_key>/<binary_name>`

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

