# Illinois Data Bank integration with Databank Archive Extractor Service

Illinois Data Bank uses the Databank Archive Extractor service to generate non-blocking previews for archive-type datafiles.

Service repository:

- https://github.com/medusa-project/databank-archive-extractor

Planning and implementation sequencing details are tracked in:

- [Archive extractor plan](archive-extractor-plan.md)

## Architecture overview

Archive extraction is an asynchronous two-message flow:

1. Illinois Data Bank sends an extraction command to ECS/Fargate.
2. Extractor downloads the source binary, computes preview metadata, and writes JSON to message storage (`messages/<web_id>.json`).
3. Extractor sends an SQS envelope containing `bucket_name`, `object_key`, `s3_status`, and `error`.
4. Illinois Data Bank consumes the SQS envelope, reads the JSON response file from message storage, updates preview fields on the datafile, and stores request/response/error records.

This mirrors the existing legacy behavior while keeping curator workflows non-blocking.

## Data contracts

The extractor service emits two distinct JSON payloads.

### 1) SQS envelope payload

This is the message body read from SQS.

```json
{
	"bucket_name": "test-bucket",
	"object_key": "messages/test-zip.json",
	"s3_status": "success",
	"error": []
}
```

Notes:

- `object_key` points to the response JSON file in message storage.
- `s3_status` is `success` or `error`.
- `error` is an array of objects, usually with `error_type` and `report` on failures.

### 2) Extractor response JSON payload

This is the JSON stored at the `object_key` path (for example `messages/<web_id>.json`).

```json
{
	"web_id": "test-zip",
	"status": "success",
	"error": [],
	"peek_type": "listing",
	"peek_text": "<span class='glyphicon glyphicon-folder-open'></span> test.zip<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>",
	"nested_items": [
		{
			"item_name": "test.txt",
			"item_path": "test.txt",
			"item_size": 12,
			"media_type": "text/plain",
			"is_directory": false
		}
	]
}
```

Notes:

- `status` is `success` or `error`.
- Extractor currently uses `peek_type` values `listing` and `none`.
- `nested_items` may be empty.
- `error` may include extraction, S3 get/put, or processing error objects.

## ECS/Fargate invocation contract

Extractor execution is performed via `run_task` with one container override command:

```ruby
command = [
	"ruby", "-r", "./lib/extractor.rb", "-e",
	"Extractor.extract '#{bucket}', '#{object_key}', '#{binary_name}', '#{web_id}', '#{mime_type}'"
]
```

Required ECS task fields:

- `cluster`
- `task_definition`
- `platform_version`
- `network_configuration.awsvpc_configuration.subnets`
- `network_configuration.awsvpc_configuration.security_groups`
- `overrides.container_overrides[0].name`
- `launch_type: FARGATE`
- `count: 1`

## Environment configuration

Known extractor infrastructure values:

### Demo

- region: `us-east-2`
- cluster: `databank-archive-extractor-demo`
- task definition: `databank-archive-extractor-demo-td:4`
- subnets: `subnet-0424eec96a8825bef`, `subnet-0fd12f3454f7faf07`
- security group: `sg-0ca863c0dcd6b0ba7`
- platform version: `1.4.0`
- container name: `databank-archive-extractor-demo-task`

### Production

- region: `us-east-2`
- cluster: `databank-archive-extractor-prod`
- task definition: `databank-archive-extractor-prod-td:4`
- subnets: `subnet-0424eec96a8825bef`, `subnet-0fd12f3454f7faf07`
- security group: `sg-0ca863c0dcd6b0ba7`
- platform version: `1.4.0`
- container name: `databank-archive-extractor-prod-task`

### App-side settings to carry in databank-2

The application should expose/configure:

- extractor enabled flag
- AWS region
- SQS queue URL
- ECS cluster
- ECS task definition
- ECS container name
- subnet list
- security group list
- platform version
- max task capacity
- max batch size

## databank-2 integration responsibilities

The databank-2 integration should implement and maintain:

1. request/response/error persistence models for traceability and troubleshooting
2. service class to invoke ECS tasks
3. service class to poll SQS and consume response files
4. datafile preview updates (`peek_type` and preview content)
5. recurring background polling job
6. rake tasks for extraction send/poll/cleanup operations
7. development mocks (no real AWS dependency locally)

## Operational flow (target)

1. Create an extract request for an eligible archive-type datafile.
2. Send extraction task(s) respecting cluster and batch limits.
3. Poll SQS for extractor envelope messages.
4. For each envelope, load response JSON from message storage.
5. Persist parsed response and any extracted errors.
6. Update datafile preview metadata from response values.
7. Delete processed response message object and acknowledge SQS receipt.

## Error handling expectations

Consumer logic should explicitly handle:

- SQS receive/delete failures
- missing `object_key` in envelope
- missing response file in message storage
- invalid JSON in response file
- missing/unknown `web_id`
- extractor response `status = error`
- malformed `nested_items`
- transient AWS availability problems

When errors occur, preserve raw payloads where possible and record enough context to support replay/retry operations.

## Troubleshooting

1. Confirm extractor is enabled and environment-specific ECS config is loaded.
2. Confirm SQS queue URL and permissions are valid.
3. Confirm response files are being written under `messages/<web_id>.json` in message storage.
4. Verify SQS envelope includes expected keys (`bucket_name`, `object_key`, `s3_status`, `error`).
5. Verify extractor response JSON includes expected keys (`web_id`, `status`, `peek_type`, `peek_text`, `nested_items`, `error`).
6. Inspect persisted request/response/error records for correlation and raw payload data.
7. Run poll/send rake tasks manually in low batch mode to isolate faults.

## References

- Extractor service code: https://github.com/medusa-project/databank-archive-extractor
