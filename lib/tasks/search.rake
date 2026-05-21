namespace :search do
  desc "Enqueue Solr reindex jobs for all datasets"
  task reindex_all: :environment do
    total = 0

    Dataset.find_in_batches(batch_size: 500) do |batch|
      batch.each do |dataset|
        Search::IndexDatasetJob.perform_later(dataset.id)
        total += 1
      end
    end

    puts "Enqueued #{total} dataset reindex jobs"
  end
end
