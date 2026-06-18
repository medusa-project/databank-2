require "rails_helper"

RSpec.describe "Datasets search", type: :request do
  def login_as(email:, name:, role: nil)
    post "/auth/developer/callback", params: { email: email, name: name, role: role || "depositor" }

    user = User.find_by!(provider: "developer", uid: email)
    user.update!(role: role) if role.present?
    user
  end

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

    get datasets_path, params: { q: "climate", subjects: [ "Earth Systems" ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_one.title)
    expect(response.body).to include("Apply Filters")
    expect(response.body).to include('<div class="idb-page-title">')
    expect(response.body).to include("<h1>Dataset Search</h1>")
    expect(response.body).not_to include('slot="title"')
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

  it "shows depositor drafts for the logged in depositor only" do
    login_as(email: "owner1@example.edu", name: "Owner One")

    own_draft = Dataset.create!(
      title: "Owner Draft Dataset",
      description: "Visible to owner",
      keywords: "draft",
      subject: "Earth Systems",
      owner_uid: "owner-1",
      depositor_name: "Owner One",
      depositor_email: "owner1@example.edu",
      publication_state: :draft
    )

    Dataset.create!(
      title: "Other User Draft Dataset",
      description: "Should not be visible",
      keywords: "draft",
      subject: "Earth Systems",
      owner_uid: "owner-2",
      depositor_name: "Owner Two",
      depositor_email: "owner2@example.edu",
      publication_state: :draft
    )

    get datasets_path, params: { q: "draft" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_draft.title)
    expect(response.body).not_to include("Other User Draft Dataset")
    expect(response.body).to include("Publication State")
    expect(response.body).not_to include("Depositor")
  end

  it "shows admin-only depositor facet and all draft datasets" do
    login_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    draft_one = Dataset.create!(
      title: "Draft One",
      description: "Admin visible",
      keywords: "admin",
      subject: "Engineering",
      owner_uid: "owner-10",
      depositor_name: "Owner Ten",
      depositor_email: "owner10@example.edu",
      publication_state: :draft
    )

    draft_two = Dataset.create!(
      title: "Draft Two",
      description: "Admin visible",
      keywords: "admin",
      subject: "Biology",
      owner_uid: "owner-11",
      depositor_name: "Owner Eleven",
      depositor_email: "owner11@example.edu",
      publication_state: :draft
    )

    get datasets_path, params: { q: "admin" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(draft_one.title)
    expect(response.body).to include(draft_two.title)
    expect(response.body).to include("Depositor")
  end

  it "supports pagination with per_page and page" do
    3.times do |index|
      Dataset.create!(
        title: "Pagination Dataset #{index}",
        description: "Paged list item #{index}",
        keywords: "paging",
        subject: "Data Science",
        owner_uid: "owner-page-#{index}",
        depositor_name: "Owner #{index}",
        depositor_email: "owner-page-#{index}@example.edu",
        publication_state: :published
      )
    end

    get datasets_path, params: { q: "Pagination Dataset", per_page: 2, page: 2 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Displaying 3 - 3 of 3 in total")
  end

  it "renders adaptive pagination with an ellipsis for longer result sets" do
    220.times do |index|
      Dataset.create!(
        title: "Long Pagination Dataset #{index}",
        description: "Long pagination item #{index}",
        keywords: "long-pagination",
        subject: "Data Science",
        owner_uid: "owner-long-page-#{index}",
        depositor_name: "Owner #{index}",
        depositor_email: "owner-long-page-#{index}@example.edu",
        publication_state: :published
      )
    end

    get datasets_path, params: { q: "Long Pagination Dataset", per_page: 5, page: 20 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("datasets-page-ellipsis")
    expect(response.body).to include("Page 1")
    expect(response.body).to include("Page 44")
    expect(response.body).not_to include("Page 10")
  end

  it "renders a more description toggle for long descriptions" do
    Dataset.create!(
      title: "Long Description Dataset",
      description: "A" * 300,
      keywords: "long",
      subject: "Data Science",
      owner_uid: "owner-long",
      depositor_name: "Owner Long",
      depositor_email: "owner-long@example.edu",
      publication_state: :published
    )

    get datasets_path, params: { q: "Long Description Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("more description")
    expect(response.body).to include("data-controller=\"description-toggle\"")
  end

  it "shows top funders plus an Other bucket" do
    top_dataset = Dataset.create!(
      title: "Top Funder Dataset",
      description: "Top funder result",
      keywords: "facet-known-other-smoke",
      subject: "Data Science",
      owner_uid: "owner-top-funder",
      depositor_name: "Owner Top",
      depositor_email: "owner-top-funder@example.edu",
      publication_state: :published
    )
    top_dataset.funders.create!(code: "DOE", name: "U.S. Department of Energy (DOE)")

    other_dataset = Dataset.create!(
      title: "Other Funder Dataset",
      description: "Other funder result",
      keywords: "facet-known-other-smoke",
      subject: "Data Science",
      owner_uid: "owner-other-funder",
      depositor_name: "Owner Other",
      depositor_email: "owner-other-funder@example.edu",
      publication_state: :published
    )
    other_dataset.funders.create!(name: "Alfred P. Sloan Foundation")

    get datasets_path, params: { q: "facet-known-other-smoke" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Other (1)")
    expect(response.body).to include("U.S. Department of Energy (DOE) (1)")
    expect(response.body).to include('id="funder_doe" value="DOE"')
    expect(response.body).not_to include("Alfred P. Sloan Foundation (1)")
  end

  it "filters by the Other funder bucket" do
    top_dataset = Dataset.create!(
      title: "Top Bucket Dataset",
      description: "Top bucket result",
      keywords: "facet-other-filter-smoke",
      subject: "Engineering",
      owner_uid: "owner-top-bucket",
      depositor_name: "Owner Top Bucket",
      depositor_email: "owner-top-bucket@example.edu",
      publication_state: :published
    )
    top_dataset.funders.create!(code: "DOE", name: "U.S. Department of Energy (DOE)")

    other_dataset = Dataset.create!(
      title: "Other Bucket Dataset",
      description: "Other bucket result",
      keywords: "facet-other-filter-smoke",
      subject: "Engineering",
      owner_uid: "owner-other-bucket",
      depositor_name: "Owner Other Bucket",
      depositor_email: "owner-other-bucket@example.edu",
      publication_state: :published
    )
    other_dataset.funders.create!(name: "Alfred P. Sloan Foundation")

    get datasets_path, params: { q: "facet-other-filter-smoke", funders: [ Search::DatasetSearch::OTHER_FUNDER_VALUE ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Other Bucket Dataset")
    expect(response.body).not_to include("Top Bucket Dataset")
  end

  it "filters by top funder code" do
    top_dataset = Dataset.create!(
      title: "Code Filter Top Dataset",
      description: "Top code filter result",
      keywords: "code-filter",
      subject: "Engineering",
      owner_uid: "owner-code-top",
      depositor_name: "Owner Code Top",
      depositor_email: "owner-code-top@example.edu",
      publication_state: :published
    )
    top_dataset.funders.create!(code: "DOE", name: "U.S. Department of Energy (DOE)")

    other_dataset = Dataset.create!(
      title: "Code Filter Other Dataset",
      description: "Other code filter result",
      keywords: "code-filter",
      subject: "Engineering",
      owner_uid: "owner-code-other",
      depositor_name: "Owner Code Other",
      depositor_email: "owner-code-other@example.edu",
      publication_state: :published
    )
    other_dataset.funders.create!(name: "Alfred P. Sloan Foundation")

    get datasets_path, params: { q: "code-filter", funders: [ "DOE" ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Code Filter Top Dataset")
    expect(response.body).not_to include("Code Filter Other Dataset")
  end

  it "accepts legacy name-based funder filter values" do
    top_dataset = Dataset.create!(
      title: "Legacy Name Filter Top Dataset",
      description: "Top legacy filter result",
      keywords: "legacy-name-filter",
      subject: "Engineering",
      owner_uid: "owner-legacy-top",
      depositor_name: "Owner Legacy Top",
      depositor_email: "owner-legacy-top@example.edu",
      publication_state: :published
    )
    top_dataset.funders.create!(code: "DOE", name: "U.S. Department of Energy (DOE)")

    other_dataset = Dataset.create!(
      title: "Legacy Name Filter Other Dataset",
      description: "Other legacy filter result",
      keywords: "legacy-name-filter",
      subject: "Engineering",
      owner_uid: "owner-legacy-other",
      depositor_name: "Owner Legacy Other",
      depositor_email: "owner-legacy-other@example.edu",
      publication_state: :published
    )
    other_dataset.funders.create!(name: "Alfred P. Sloan Foundation")

    get datasets_path, params: { q: "legacy-name-filter", funders: [ "U.S. Department of Energy (DOE)" ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Legacy Name Filter Top Dataset")
    expect(response.body).not_to include("Legacy Name Filter Other Dataset")
  end

  it "keeps top facet assignment stable when funder name differs but code stays known" do
    dataset = Dataset.create!(
      title: "Renamed Funder Dataset",
      description: "Renamed funder result",
      keywords: "renamed-funder",
      subject: "Data Science",
      owner_uid: "owner-renamed-funder",
      depositor_name: "Owner Renamed",
      depositor_email: "owner-renamed-funder@example.edu",
      publication_state: :published
    )
    dataset.funders.create!(code: "DOE", name: "Department of Energy (Renamed)")

    get datasets_path, params: { q: "renamed-funder" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("U.S. Department of Energy (DOE) (1)")
    expect(response.body).not_to include("Other (1)")
  end

  it "matches text query by funder name" do
    matching_dataset = Dataset.create!(
      title: "Dataset With NIH Funder",
      description: "query by funder name",
      keywords: "nih-query",
      subject: "Data Science",
      owner_uid: "owner-nih-query",
      depositor_name: "Owner NIH",
      depositor_email: "owner-nih-query@example.edu",
      publication_state: :published
    )
    matching_dataset.funders.create!(code: "NIH", name: "U.S. National Institutes of Health (NIH)")

    Dataset.create!(
      title: "Dataset Without NIH Funder",
      description: "does not match by funder",
      keywords: "nih-query",
      subject: "Data Science",
      owner_uid: "owner-no-nih-query",
      depositor_name: "Owner No NIH",
      depositor_email: "owner-no-nih-query@example.edu",
      publication_state: :published
    )

    get datasets_path, params: { q: "National Institutes of Health" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dataset With NIH Funder")
    expect(response.body).not_to include("Dataset Without NIH Funder")
  end
end
