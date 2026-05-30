FactoryBot.define do
  factory :user do
    provider { "developer" }
    sequence(:uid) { |n| "user-#{n}" }
    sequence(:email) { |n| "user#{n}@example.edu" }
    name { "Factory User" }
    username { email }
    role { "depositor" }

    trait :admin do
      role { "admin" }
    end
  end
end
