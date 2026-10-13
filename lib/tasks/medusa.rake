namespace :medusa do
  desc "Reconcile all_medusa flag for datasets based on current datafile storage_root values"
  task reconcile_all_medusa: :environment do
    dataset_key = ENV["DATASET_KEY"].to_s.strip.presence
    scope = dataset_key.present? ? Dataset.where(key: dataset_key) : Dataset.all

    updated_true = 0
    updated_false = 0

    scope.find_each do |dataset|
      next if dataset.datafiles.empty?

      all_in_medusa = dataset.datafiles.all? { |df| df.storage_root == "medusa" }
      if all_in_medusa && !dataset.all_medusa
        dataset.update(all_medusa: true)
        updated_true += 1
      elsif !all_in_medusa && dataset.all_medusa
        dataset.update(all_medusa: false)
        updated_false += 1
      end
    end

    puts JSON.pretty_generate(dataset_key: dataset_key, updated_true: updated_true, updated_false: updated_false)
  end
end
