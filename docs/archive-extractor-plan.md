Plan: Archive Extractor Service Integration
TL;DR:
Port the legacy archive extractor integration to databank-2, implementing models (ArchiveExtractRequest, ArchiveExtractResponse, ArchiveExtractError), a service layer to invoke AWS Fargate tasks and poll SQS responses, rake tasks for batch extraction jobs, and automatic peek metadata population on datafiles. Curators will be able to extract archive previews on draft datasets (non-blocking), not just at publish time. Use SolidQueue for recurring response polling; mock the extractor for local development.

Steps
Phase 1: Database Models & Schema (blocks all downstream work)
Create migration adding peek_type and peek_content (text) columns to datafiles table
Create ArchiveExtractRequest model
Attributes: datafile_id, sent_at, response_at, status (enum: pending/sent/success/failed), raw_response (text for full SQS message)
Associations: belongs_to :datafile, has_one :archive_extract_response (dependent: :destroy), has_many :archive_extract_errors (through response)
Validations: datafile_id presence, web_id uniqueness (via datafile)
Create ArchiveExtractResponse model
Attributes: archive_extract_request_id, status, response (jsonb for parsed extractor output)
Associations: belongs_to :archive_extract_request, has_many :archive_extract_errors (dependent: :destroy)
Create ArchiveExtractError model
Attributes: archive_extract_response_id, error_type (string), error_report (text)
Associations: belongs_to :archive_extract_response
Cleanup handled by rake task using created_at retention cutoff (no extra migration needed)
Update Datafile model: add association (has_one :archive_extract_request)
Phase 2: Fargate Invocation Service (depends on Phase 1)
Create ArchiveExtractor::FargateInvoker service class

Initialize with AWS ECS client (using Rails credentials: extractor.aws_region, extractor.ecs_cluster)
invoke_extraction(datafile) method that:
Creates ArchiveExtractRequest record with status: :sent
Builds Fargate run_task parameters (cluster, task definition, container overrides with extraction command)
Calls ECS client run_task()
Returns ArchiveExtractRequest on success, raises on failure
Command format: Extractor.extract '<storage_root>', '<storage_key>', '<binary_name>', '<datafile_web_id>', '<mime_type>'
Handle prod vs. demo environment config (cluster name from IDB_CONFIG[:extractor][:cluster])
Mock class ArchiveExtractor::MockInvoker for development (returns stub ArchiveExtractRequest)
Create ArchiveExtractor::ResponseConsumer service class

Initialize with AWS SQS client (credentials: extractor.aws_sqs_queue_url)
poll_responses(batch_size: 10) method that:
Receives up to batch_size messages from SQS
For each message: parse SQS envelope (`bucket_name`, `object_key`, `s3_status`, `error`)
Read response JSON file from Medusa message storage (legacy pattern) using object_key basename
Parse response web_id -> find ArchiveExtractRequest by datafile.web_id
Parse JSON response, create ArchiveExtractResponse + ArchiveExtractErrors
Update datafile.peek_type and peek_content from response.peek_type/response.peek_text
Delete message file and SQS message (mark received)
Return summary of processed/failed
Mock class ArchiveExtractor::MockResponseConsumer for development (no-op or reads test fixtures)
Phase 3: Rake Tasks for Batch Extraction (depends on Phase 2)
Create lib/tasks/archive_extractor.rake with namespace:
extractor:extract_pending — Invoke pending ArchiveExtractRequests in batches, respecting Fargate cluster capacity (max ~49 tasks)

Query unsent ArchiveExtractRequests, validate associated datafile exists, invoke via FargateInvoker
Emit summary (sent count, skipped, errors)
Respects DATASET_KEY=... environment variable for scoped extraction
Respects DRY_RUN=true for preview
extractor:poll_responses — Consume pending SQS responses via ResponseConsumer

Respects BATCH_SIZE=10 environment variable
Logs all processed/failed summaries
extractor:cleanup_old_records — Delete ArchiveExtractRequest/Response/Error records older than 30 days

Optional DAYS_TO_RETAIN=30 environment variable
DRY_RUN support
extractor:send_batch_test (dev only) — Create test ArchiveExtractRequest for smoke testing

Phase 4: Recurring SolidQueue Job (depends on Phase 2, Phase 3 optional)
Create app/jobs/archive_extract_response_job.rb
Runs every minute (add to recurring.yml)
Calls ArchiveExtractor::ResponseConsumer.new.poll_responses(batch_size: 50)
Logs all results, allows graceful degradation on SQS unavailability
Sets job status/error tracking for ops monitoring
Phase 5: Trigger Points for Extraction (depends on Phase 1, Phase 2)
Add UI hook in datafile show/edit view to manually trigger extraction (button/link)

Action in DatafilesController: creates ArchiveExtractRequest, enqueues immediate or deferred extraction via rake task
Only for archive-type files (via MIME type check)
Response shows modal with extraction status
Optional: Auto-trigger on datafile upload

In DatafilesController#create or upload handler, create ArchiveExtractRequest if file is archive type
Non-blocking (user can continue editing draft)
Phase 6: Configuration & Credentials (depends on Phase 1)
Add to credentials.yml.enc (via bin/rails credentials:edit):


extractor:  enabled: true  aws_region: "us-east-2"  aws_sqs_queue_url: "https://sqs.us-east-2.amazonaws.com/721945215539/..."  ecs_cluster: "databank-archive-extractor-prod"  ecs_task_definition: "databank-archive-extractor-prod-td:4"  ecs_container_name: "databank-archive-extractor-prod-task"  max_task_capacity: 49  max_batch_size: 9
Add environment-specific overrides in config/environments/*.rb:

Production: use prod Fargate cluster/task def
Demo: use demo Fargate cluster/task def
Development: disable real Fargate, enable mocks
Add to IdbConfig initialization to load extractor settings

Port AWS credentials (access key, secret) from legacy app to Rails master.key or environment

Phase 7: Local Development Mocking (depends on Phase 2, Phase 6)
Create lib/archive_extractor/mock_invoker.rb and lib/archive_extractor/mock_response_consumer.rb

MockInvoker returns ArchiveExtractRequest with stub data
MockResponseConsumer simulates response from test fixtures (e.g., spec/fixtures/archive_extractor_responses.json)
In development env, conditionally load mocks instead of real Fargate/SQS
Create test fixtures for common archive types (ZIP, TAR, image previews, markdown)

Update local dev docs to explain mock behavior

Phase 8: Tests (depends on Phases 1-7)
Model specs (app/models/):

ArchiveExtractRequest: validations, associations, state transitions
ArchiveExtractResponse: parsing, error aggregation
ArchiveExtractError: error recording
Service specs (app/services/ or spec/services/):

FargateInvoker: ECS client mocking, command string formatting, cluster/task def selection
ResponseConsumer: SQS message parsing, datafile peek update, error handling
Both invoker & consumer mock behavior in unit tests
Job specs (app/jobs/):

ArchiveExtractResponseJob: recurring execution, error recovery
Integration specs:

Full flow: create ArchiveExtractRequest → invoke Fargate (mocked) → receive response → update datafile peek
Error cases: missing datafile, invalid response format, SQS unavailability
Rake task specs:

extractor:extract_pending — batch extraction, dry-run, dataset scoping
extractor:poll_responses — response consumption, cleanup
extractor:cleanup_old_records — retention policy
Phase 9: Documentation (can parallelize with implementation)
Expand archive-extractor-integration.md:

Architecture overview (Fargate invocation, SQS polling, peek population)
Model definitions and state machine
Configuration reference (credentials.yml keys, environment precedence)
Operational runbooks:
Manual extraction trigger (rake task or UI button)
Monitor pending/failed requests
Troubleshoot SQS or Fargate failures
30-day cleanup retention policy
Local dev setup (mock behavior, test fixtures)
Examples of response structures and peek types
Update README.md Troubleshooting section with extractor-specific links if needed

Relevant Files
Database & Models:

datafile.rb — add peek_type/peek_content, associations
(new) app/models/archive_extract_request.rb
(new) app/models/archive_extract_response.rb
(new) app/models/archive_extract_error.rb
(new) db/migrate/XXXXXXXXX_create_archive_extractor_tables.rb — models, pk/fk, indexes
(new) db/migrate/XXXXXXXXX_add_peek_to_datafiles.rb — peek_type, peek_content columns
Services:

(new) app/services/archive_extractor/fargate_invoker.rb
(new) app/services/archive_extractor/mock_invoker.rb
(new) app/services/archive_extractor/response_consumer.rb
(new) app/services/archive_extractor/mock_response_consumer.rb
Jobs & Tasks:

(new) app/jobs/archive_extract_response_job.rb
(new) lib/tasks/archive_extractor.rake
Configuration:

recurring.yml — add archive_extract_response_job entry
credentials.yml.enc — add extractor config keys
production.rb, demo.rb, development.rb — set invoker/consumer class per env
idb_config.rb — load extractor settings
UI/Controllers (if Phase 5 included):

datafiles_controller.rb — add trigger_extraction action
app/views/datafiles/show.html.erb — add extraction button
Tests:

(new) spec/models/archive_extract_request_spec.rb
(new) spec/models/archive_extract_response_spec.rb
(new) spec/services/archive_extractor/fargate_invoker_spec.rb
(new) spec/services/archive_extractor/response_consumer_spec.rb
(new) spec/jobs/archive_extract_response_job_spec.rb
Documentation:

archive-extractor-integration.md — comprehensive update (architecture, config, operations, troubleshooting)
local-pre-push-checklist.md — add mock extractor test if needed
extractor_tasks.rake — reference for legacy patterns
Verification
Phase 1: Run rails db:migrate and verify table structure: datafiles (peek_type, peek_content), archive_extract_requests, archive_extract_responses, archive_extract_errors
Phase 2: Unit specs for FargateInvoker and ResponseConsumer pass; mock classes return expected structures
Phase 3: Rake tasks executable: bundle exec rake extractor:extract_pending DRY_RUN=true shows dry-run output without creating records
Phase 4: SolidQueue recurring job appears in queue worker logs; runs every minute without errors
Phase 6: Credentials load correctly; Rails.application.credentials.extractor returns expected hash
Phase 7: Development environment uses mocks; extraction creates stub ArchiveExtractRequest without calling Fargate
Phase 8: Full integration spec: create ArchiveExtractRequest → invoke (mocked) → receive response → verify datafile.peek_type and peek_content updated
Phase 9: Documentation builds without broken links; includes all config keys, operational examples, troubleshooting steps
Decisions
Model Naming: Renamed ExtractorTask -> ArchiveExtractRequest to avoid collision with Rails job terminology and reduce confusion about what "Task" means
Peek Attributes: Added peek_type and peek_content (mapped from extractor response `peek_type` and `peek_text`). Minimal schema following user preference
Trigger Strategy: Non-blocking async extraction on curator action (manual UI trigger), not automatic on publish. Curators can extract previews on draft datasets before publishing
Architecture: Two-part communication: ECS SDK for job submission (Fargate), SQS polling for responses (via recurring SolidQueue job). Aligns with legacy pattern, decouples publish workflow from extractor latency
Persistence: Full models (Request/Response/Error) with database persistence for troubleshooting and state tracking. Includes 30-day cleanup mechanism via rake task
Local Dev: Complete mock strategy (no Docker required). Uses test fixtures for realistic response simulation
Credentials: Port from legacy app (AWS region, SQS queue URL, Fargate cluster/task def). Store in Rails credentials.yml.enc for safety
Further Considerations
Fargate Capacity Monitoring: Consider adding dashboard or alerts if task queue grows. Current implementation respects max capacity (~49 tasks) but doesn't expose metrics. Optional follow-up: emit CloudWatch metrics or internal counters
Response Parsing Robustness: Legacy extractor JSON responses vary. Need to define canonical response schema and handle graceful degradation for unexpected formats. Recommend validation layer in ResponseConsumer before datafile updates
UI/UX Polish: Phase 5 assumes basic extraction button. Consider: progress indicators (polling status), retry UI for failed extractions, preview of extracted content in modal. These can be Phase 2 enhancements
That's the comprehensive plan. Would you like me to refine any section, ask clarifying questions about naming or phasing, or are you ready to hand off for implementation?