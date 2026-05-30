FactoryBot.define do
  factory :datafile do
    association :dataset
    sequence(:binary_name) { |n| "analysis-#{n}.csv" }
    description { "Factory datafile" }

    transient do
      attach_binary { true }
    end

    after(:build) do |datafile, evaluator|
      next unless evaluator.attach_binary
      next if datafile.binary.attached?

      datafile.binary.attach(
        io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/analysis.csv"))),
        filename: "analysis.csv",
        content_type: "text/csv"
      )
      datafile.sync_metadata_from_attachment!
    end
  end
end
