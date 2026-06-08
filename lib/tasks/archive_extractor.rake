namespace :archive_extractor do
  def archive_extractor_invoker
    if ArchiveExtractor::Config.use_mocks?
      ArchiveExtractor::MockInvoker.new
    else
      ArchiveExtractor::FargateInvoker.new
    end
  end

  def archive_extractor_consumer
    if ArchiveExtractor::Config.use_mocks?
      ArchiveExtractor::MockResponseConsumer.new
    else
      ArchiveExtractor::ResponseConsumer.new
    end
  end

  desc "Send pending archive extraction requests"
  task extract_pending: :environment do
    unless ArchiveExtractor::Config.enabled? || ArchiveExtractor::Config.use_mocks?
      puts "Extractor integration is disabled."
      next
    end

    dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?
    max_batch = ENV.fetch("MAX_BATCH", ArchiveExtractor::Config.max_batch_size).to_i

    invoker = archive_extractor_invoker
    available_capacity = [ ArchiveExtractor::Config.max_task_capacity - invoker.current_task_count.to_i, 0 ].max
    limit = [ max_batch, available_capacity ].min

    if limit <= 0
      puts "No extractor capacity available."
      next
    end

    scope = ArchiveExtractRequest.pending.includes(:datafile)
    if ENV["DATASET_KEY"].present?
      scope = scope.joins(datafile: :dataset).where(datasets: { key: ENV["DATASET_KEY"] })
    end

    sent = 0
    failed = 0

    scope.limit(limit).find_each do |request|
      if dry_run
        puts "[DRY RUN] Would invoke extractor for #{request.datafile.web_id}"
        next
      end

      begin
        invoker.invoke_extraction(request.datafile)
        sent += 1
      rescue StandardError => e
        failed += 1
        puts "Failed to invoke extractor for #{request.datafile.web_id}: #{e.message}"
      end
    end

    puts "Extractor requests sent: #{sent}, failed: #{failed}, limit: #{limit}"
  end

  desc "Poll SQS responses from archive extractor"
  task poll_responses: :environment do
    unless ArchiveExtractor::Config.enabled? || ArchiveExtractor::Config.use_mocks?
      puts "Extractor integration is disabled."
      next
    end

    batch_size = ENV.fetch("BATCH_SIZE", "10").to_i
    summary = archive_extractor_consumer.poll_responses(batch_size: batch_size)

    puts "Processed: #{summary.processed}, Succeeded: #{summary.succeeded}, Failed: #{summary.failed}, Skipped: #{summary.skipped}"
  end

  desc "Delete archive extractor records older than retention days"
  task cleanup_old_records: :environment do
    retention_days = ENV.fetch("RETENTION_DAYS", "30").to_i
    dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?
    cutoff = retention_days.days.ago

    scope = ArchiveExtractRequest.where("created_at < ?", cutoff)
    count = scope.count

    if dry_run
      puts "[DRY RUN] Would remove #{count} archive extract requests older than #{retention_days} days."
      next
    end

    deleted = scope.destroy_all.count
    puts "Removed #{deleted} archive extract requests older than #{retention_days} days."
  end

  desc "Create and invoke pending requests for sample archive datafiles"
  task send_batch_test: :environment do
    limit = ENV.fetch("LIMIT", "5").to_i
    dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

    archive_scope = Datafile
      .where("lower(binary_mime_type) LIKE ?", "application/%zip%")
      .or(Datafile.where("lower(binary_mime_type) LIKE ?", "%tar%"))
      .or(Datafile.where("lower(binary_mime_type) LIKE ?", "%gzip%"))
      .limit(limit)

    created = 0
    archive_scope.find_each do |datafile|
      request = datafile.archive_extract_request || datafile.build_archive_extract_request
      if request.new_record?
        request.status = :pending
        request.save!
        created += 1
      end

      puts "Prepared request for #{datafile.web_id}"
      puts "[DRY RUN] Skipped invoke for #{datafile.web_id}" if dry_run
    end

    puts "Prepared #{created} new pending archive extraction requests."

    next if dry_run

    Rake::Task["archive_extractor:extract_pending"].reenable
    Rake::Task["archive_extractor:extract_pending"].invoke
  end
end
