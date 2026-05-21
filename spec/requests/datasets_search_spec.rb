require "rails_helper"

RSpec.describe "Datasets search", type: :request do
  it "searches published datasets by query and subject" do
    dataset_one = Dataset.create!(
      title: "Climate Trend Data",
      description: "Long-term climate observations",
      keywords: "climate,temperature",
      subject: "Earth Systems",
      owner_uid: "owner-1",
      depositor_name: "Owner One",
      depositor_email: "owner1@example.edu",
      publication_state: :published
    )

    Dataset.create!(
      title: "Marine Biology Survey",
      description: "Coastal species records",
      keywords: "ocean,biodiversity",
      subject: "Marine Science",
      owner_uid: "owner-2",
      depositor_name: "Owner Two",
      depositor_email: "owner2@example.edu",
      publication_state: :published
    )

    get datasets_path, params: { q: "climate", subject: "Earth Systems" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_one.title)
    expect(response.body).to include("Apply Filters")
    expect(response.body).not_to include("Marine Biology Survey")
  end

  it "does not show draft datasets to guests in search results" do
    Dataset.create!(
      title: "Draft Climate Dataset",
      description: "Should not be visible",
      keywords: "climate",
      subject: "Earth Systems",
      owner_uid: "owner-3",
      depositor_name: "Owner Three",
      depositor_email: "owner3@example.edu",
      publication_state: :draft
    )

    get datasets_path, params: { q: "climate" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Draft Climate Dataset")
  end
end
