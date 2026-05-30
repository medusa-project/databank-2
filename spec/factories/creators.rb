FactoryBot.define do
  factory :creator do
    association :dataset
    name { "Factory Creator" }
    given_name { "Factory" }
    family_name { "Creator" }
    email { "creator@example.edu" }
    contact { false }
    is_contact { false }
    row_position { 1 }
  end
end
