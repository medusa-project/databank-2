require "rails_helper"

RSpec.describe "Dataset record text", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "renders record text for a public published dataset" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/IDB-RECORDTEXT",
      title: "Record Text Dataset",
      publisher: "Illinois Data Bank"
    )
    create(:datafile, dataset: dataset, binary_name: "analysis.csv", binary_size: 10_240)

    get record_text_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("DOI:")
    expect(response.body).to include("10.5555/IDB-RECORDTEXT")
    expect(response.body).to include("analysis.csv")
  end

  it "requires sign in for non-public draft dataset" do
    dataset = create(:dataset, publication_state: :draft)

    get record_text_dataset_path(dataset)

    expect(response).to redirect_to(login_path)
  end
end
