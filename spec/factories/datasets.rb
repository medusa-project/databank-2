FactoryBot.define do
  factory :dataset do
    sequence(:title) { |n| "Dataset #{n}" }
    description { "Dataset description" }
    keywords { "test,metadata" }
    subject { "Data Science" }
    license { "CC0" }
    publisher { "Illinois Data Bank" }
    sequence(:owner_uid) { |n| "owner-#{n}" }
    depositor_name { "Owner User" }
    sequence(:depositor_email) { |n| "owner#{n}@example.edu" }
    publication_state { :draft }
    embargo { Dataset::EMBARGO_NONE }
    release_date { nil }

    trait :published do
      publication_state { :published }
      with_required_metadata
    end

    trait :with_required_metadata do
      after(:build) do |dataset|
        next if dataset.creators.any?(&:contact_selected?)

        dataset.creators.build(
          name: "Factory Contact Creator",
          email: "creator@example.edu",
          contact: true,
          row_position: 1
        )
      end

      after(:create) do |dataset|
        create(:datafile, dataset: dataset) if dataset.datafiles.empty?
      end
    end

    trait :embargo_file_unreleased do
      embargo { Dataset::EMBARGO_FILE }
      release_date { Date.current + 30 }
    end

    trait :embargo_metadata_unreleased do
      embargo { Dataset::EMBARGO_METADATA }
      release_date { Date.current + 30 }
    end

    trait :embargo_metadata_released do
      embargo { Dataset::EMBARGO_METADATA }
      release_date { Date.current - 1 }
    end
  end
end
