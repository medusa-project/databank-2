# frozen_string_literal: true

require "open-uri"

namespace :db do
  namespace :sessions do
    desc "Trim old sessions from the table (default: > 30 days)"
    task trim: :environment do
      connection = ActiveRecord::Base.connection
      unless connection.data_source_exists?("sessions")
        puts "Skipping session trim: sessions table does not exist."
        next
      end

      days = ENV.fetch("TRIM_AFTER_DAYS", "30").to_i
      cutoff = days.days.ago

      columns = connection.columns("sessions").map(&:name)
      timestamp_column = if columns.include?("updated_at")
        "updated_at"
      elsif columns.include?("created_at")
        "created_at"
      end

      unless timestamp_column
        puts "Skipping session trim: sessions table has no created_at/updated_at column."
        next
      end

      table_name = connection.quote_table_name("sessions")
      column_name = connection.quote_column_name(timestamp_column)
      cutoff_value = connection.quote(cutoff)
      sql = "DELETE FROM #{table_name} WHERE #{column_name} < #{cutoff_value}"

      deleted = connection.delete(sql)
      puts "Trimmed #{deleted} sessions older than #{days} days."
    end
  end
end

namespace :pub do
  desc "Update publication state for datasets with current or past release date"
  task update_state: :environment do
    updated = 0

    Dataset.find_each do |dataset|
      next unless dataset.published?
      next unless dataset.file_embargoed? || dataset.metadata_embargoed?
      next unless dataset.release_date.present? && dataset.release_date <= Date.current

      dataset.embargo = Dataset::EMBARGO_NONE
      if dataset.save
        updated += 1
      else
        warn "pub:update_state failed for #{dataset.key}: #{dataset.errors.full_messages.to_sentence}"
      end
    end

    puts "Updated #{updated} published dataset(s) whose embargo release date has passed."
  end
end

namespace :sunspot do
  desc "Compatibility task for legacy Sunspot reindex cron hooks"
  task :reindex, %i[batch_size models silence] => :environment do |_task, _args|
    # databank-2 search is backed by Postgres queries; no Solr/Sunspot reindex is required.
    puts "sunspot:reindex is a no-op in databank-2 (no Solr/Sunspot index)."
  end
end

namespace :databank do
  desc "Remove download records with IP addresses older than 3 days"
  task scrub_download_records: :environment do
    deleted = DayFileDownload.where("download_date < ?", 3.days.ago.to_date).delete_all
    puts "Removed #{deleted} day download record(s) older than 3 days."
  end
end

namespace :extractor_tasks do
  desc "Get and handle message from Illinois Data Bank archive extractor"
  task get_extractor_response: :environment do
    previous_batch = ENV["BATCH_SIZE"]
    ENV["BATCH_SIZE"] = "1" if previous_batch.blank?

    Rake::Task["archive_extractor:poll_responses"].reenable
    Rake::Task["archive_extractor:poll_responses"].invoke
  ensure
    ENV["BATCH_SIZE"] = previous_batch
  end

  desc "Initiate as many archive extraction tasks as capacity allows"
  task send_batch: :environment do
    Rake::Task["archive_extractor:extract_pending"].reenable
    Rake::Task["archive_extractor:extract_pending"].invoke
  end
end

namespace :experts do
  desc "Generate export doc"
  task generate_doc: :environment do
    output_path = Rails.root.join("public", "illinois_experts.xml")
    File.write(output_path, Dataset.to_illinois_experts)
    puts "Wrote #{output_path}"
  end

  desc "Fetch demo export doc"
  task fetch_demo_doc: :environment do
    source_url = ENV.fetch("DEMO_EXPERTS_URL", "https://demo.databank.illinois.edu/illinois_experts.xml")
    output_path = Rails.root.join("public", "illinois_experts_demo.xml")

    doc = URI.open(source_url, &:read)
    File.write(output_path, doc)
    puts "Wrote #{output_path} from #{source_url}"
  end
end

namespace :globus do
  desc "Copy datasets to globus (legacy alias)"
  task copy_datasets: :environment do
    Rake::Task["globus:copy_public_datafiles"].reenable
    Rake::Task["globus:copy_public_datafiles"].invoke
  end
end

namespace :medusa do
  desc "Get Medusa ingest response messages"
  task get_medusa_ingest_responses: :environment do
    consumer = Ingest::RabbitmqResponseConsumer.new
    unless consumer.enabled?
      puts "Ingest response consumer is disabled."
      next
    end

    max_messages = ENV.fetch("BATCH_SIZE", IdbConfig.fetch(:ingest, :response_batch_size, default: "50")).to_i
    result = consumer.consume_batch(max_messages: max_messages)

    puts "Processed: #{result.processed}, Matched: #{result.matched}, Unmatched: #{result.unmatched}, Invalid: #{result.invalid}"
  end
end
