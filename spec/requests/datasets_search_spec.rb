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
    expect(response.body).to include("Clear Filters")
    expect(response.body).to include('<div class="idb-page-title">')
    expect(response.body).to include("<h1>Dataset Search</h1>")
    expect(response.body).not_to include('slot="title"')
    expect(response.body).not_to include("Marine Biology Survey")
  end

  it "searches published datasets by identifier" do
    dataset = Dataset.create!(
      title: "Identifier Lookup Dataset",
      description: "Matches by DOI identifier",
      keywords: "identifier-search",
      subject: "Earth Systems",
      identifier: "10.5555/IDB-IDENTIFIER-LOOKUP",
      owner_uid: "owner-identifier-lookup",
      depositor_name: "Owner Identifier Lookup",
      depositor_email: "owner-identifier-lookup@example.edu",
      publication_state: :published
    )

    get datasets_path, params: { q: "10.5555/IDB-IDENTIFIER-LOOKUP" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset.title)
    expect(response.body).to include(dataset.identifier)
  end

  it "searches published datasets by DOI-prefixed and resolver URL identifier queries" do
    dataset = Dataset.create!(
      title: "Flexible Identifier Lookup Dataset",
      description: "Matches by normalized identifier queries",
      keywords: "identifier-search-flexible",
      subject: "Earth Systems",
      identifier: "10.5555/IDB-FLEXIBLE-LOOKUP",
      owner_uid: "owner-flexible-lookup",
      depositor_name: "Owner Flexible Lookup",
      depositor_email: "owner-flexible-lookup@example.edu",
      publication_state: :published
    )

    [
      "doi:10.5555/IDB-FLEXIBLE-LOOKUP",
      "https://doi.org/10.5555/IDB-FLEXIBLE-LOOKUP",
      "https://dx.doi.org/10.5555/IDB-FLEXIBLE-LOOKUP"
    ].each do |query|
      get datasets_path, params: { q: query }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(dataset.title)
      expect(response.body).to include(dataset.identifier)
    end
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

  it "shows external files facet only for admin role" do
    Dataset.create!(
      title: "External Files Facet Dataset",
      description: "Facet visibility dataset",
      keywords: "external-facet-visible",
      subject: "Engineering",
      owner_uid: "owner-external-facet-visible",
      depositor_name: "Owner External Facet",
      depositor_email: "owner-external-facet-visible@example.edu",
      publication_state: :published,
      external_files_link: "https://example.org/external-visible"
    )

    get datasets_path, params: { q: "external-facet-visible" }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("external_files_has_external_files")

    login_as(email: "admin-external-facet@example.edu", name: "Admin External Facet", role: "admin")
    get datasets_path, params: { q: "external-facet-visible" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("External Files")
    expect(response.body).to include("Has External Files")
    expect(response.body).to include("external_files_has_external_files")
  end

  it "filters by has external files for admins" do
    login_as(email: "admin-external-filter@example.edu", name: "Admin External Filter", role: "admin")

    Dataset.create!(
      title: "Dataset With External Files",
      description: "Has external files",
      keywords: "external-files-filter",
      subject: "Engineering",
      owner_uid: "owner-has-external-files",
      depositor_name: "Owner Has External Files",
      depositor_email: "owner-has-external-files@example.edu",
      publication_state: :published,
      external_files_note: "External repository"
    )

    Dataset.create!(
      title: "Dataset Without External Files",
      description: "No external files",
      keywords: "external-files-filter",
      subject: "Engineering",
      owner_uid: "owner-no-external-files",
      depositor_name: "Owner No External Files",
      depositor_email: "owner-no-external-files@example.edu",
      publication_state: :published,
      external_files_note: "",
      external_files_link: nil
    )

    get datasets_path, params: {
      q: "external-files-filter",
      external_files: [ Search::DatasetSearch::EXTERNAL_FILES_HAS_VALUE ]
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dataset With External Files")
    expect(response.body).not_to include("Dataset Without External Files")
  end

  it "filters by no external files for admins" do
    login_as(email: "admin-no-external-filter@example.edu", name: "Admin No External Filter", role: "admin")

    Dataset.create!(
      title: "Has External Repo Dataset",
      description: "Has external files",
      keywords: "no-external-files-filter",
      subject: "Engineering",
      owner_uid: "owner-external-included",
      depositor_name: "Owner External Included",
      depositor_email: "owner-external-included@example.edu",
      publication_state: :published,
      external_files_link: "https://example.org/external-included"
    )

    Dataset.create!(
      title: "No External Files Included Dataset",
      description: "No external files",
      keywords: "no-external-files-filter",
      subject: "Engineering",
      owner_uid: "owner-no-external-included",
      depositor_name: "Owner No External Included",
      depositor_email: "owner-no-external-included@example.edu",
      publication_state: :published,
      external_files_note: "",
      external_files_link: nil
    )

    Dataset.create!(
      title: "Whitespace External Fields Dataset",
      description: "Whitespace-only external file values should be treated as blank",
      keywords: "no-external-files-filter",
      subject: "Engineering",
      owner_uid: "owner-whitespace-external",
      depositor_name: "Owner Whitespace External",
      depositor_email: "owner-whitespace-external@example.edu",
      publication_state: :published,
      external_files_note: "   ",
      external_files_link: "   "
    )

    get datasets_path, params: {
      q: "no-external-files-filter",
      external_files: [ Search::DatasetSearch::EXTERNAL_FILES_NONE_VALUE ]
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No External Files Included Dataset")
    expect(response.body).to include("Whitespace External Fields Dataset")
    expect(response.body).not_to include("Has External Repo Dataset")
  end

  it "shows accurate publication state facet labels for curator roles" do
    login_as(email: "admin-publication-state@example.edu", name: "Admin Publication State", role: "admin")

    Dataset.create!(
      title: "Facet Draft State Dataset",
      description: "Draft state facet",
      keywords: "publication-state-facet",
      subject: "Engineering",
      owner_uid: "owner-publication-state-draft",
      depositor_name: "Owner Publication State Draft",
      depositor_email: "owner-publication-state-draft@example.edu",
      publication_state: :draft
    )

    Dataset.create!(
      title: "Facet Published State Dataset",
      description: "Published state facet",
      keywords: "publication-state-facet",
      subject: "Engineering",
      owner_uid: "owner-publication-state-published",
      depositor_name: "Owner Publication State Published",
      depositor_email: "owner-publication-state-published@example.edu",
      publication_state: :published
    )

    get datasets_path, params: { q: "publication-state-facet" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Draft (1)")
    expect(response.body).to include("Published (1)")
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

  it "shows curator-only search result badges for admins" do
    login_as(email: "admin-badges@example.edu", name: "Admin Badges", role: "admin")

    dataset = Dataset.create!(
      title: "Curator Badge Dataset",
      description: "Badge visibility dataset",
      keywords: "curator-badges",
      subject: "Earth Systems",
      owner_uid: "owner-curator-badges",
      depositor_name: "Owner Curator Badges",
      depositor_email: "owner-curator-badges@example.edu",
      publication_state: :published,
      published_at: Time.zone.parse("2026-01-15"),
      release_date: Date.new(2026, 1, 15)
    )
    dataset.notes.create!(body: "Curator note", author: "curator@example.edu")
    dataset.version_requests.create!(
      requester_email: "depositor@example.edu",
      requester_name: "Depositor User",
      requested_at: Time.zone.parse("2026-01-10"),
      status: :pending
    )

    draft_with_share = Dataset.create!(
      title: "Curator Badge Draft Share Dataset",
      description: "Draft sharing dataset",
      keywords: "curator-badges",
      subject: "Earth Systems",
      owner_uid: "owner-curator-badges-draft",
      depositor_name: "Owner Curator Badges Draft",
      depositor_email: "owner-curator-badges-draft@example.edu",
      publication_state: :draft
    )
    draft_with_share.create_token!(identifier: Token.generate_auth_token)

    get datasets_path, params: { q: "curator-badges" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("updated:")
    expect(response.body).to include("created:")
    expect(response.body).to include("ingested:")
    expect(response.body).to include("ingested: N/A")
    expect(response.body).to include("released:")
    expect(response.body).to include("released: 2026-01-15")
    expect(response.body).to include("published: 2026-01-15")
    expect(response.body).to include("version candidate under review")
    expect(response.body).to include("has sharing link")
    expect(response.body).to include("draft")
    expect(response.body).to include("Earth Systems")
    expect(response.body).to include("1 note")
    expect(response.body).to include("0 notes")
  end

  it "shows a public published date badge when dataset is published" do
    login_as(email: "admin-released-fallback@example.edu", name: "Admin Released Fallback", role: "admin")

    Dataset.create!(
      title: "Released Fallback Dataset",
      description: "Published without explicit release date",
      keywords: "released-fallback",
      subject: "Earth Systems",
      owner_uid: "owner-released-fallback",
      depositor_name: "Owner Released Fallback",
      depositor_email: "owner-released-fallback@example.edu",
      publication_state: :published,
      published_at: Time.zone.parse("2026-02-20")
    )

    get datasets_path, params: { q: "released-fallback" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("published: 2026-02-20")
  end

  it "hides curator-only search result badges from guests" do
    dataset = Dataset.create!(
      title: "Guest Badge Hidden Dataset",
      description: "Guest badge visibility dataset",
      keywords: "guest-badge-hidden",
      subject: "Earth Systems",
      owner_uid: "owner-guest-badge-hidden",
      depositor_name: "Owner Guest Hidden",
      depositor_email: "owner-guest-badge-hidden@example.edu",
      publication_state: :published,
      published_at: Time.zone.parse("2026-01-15"),
      release_date: Date.new(2026, 1, 15)
    )
    dataset.notes.create!(body: "Curator note", author: "curator@example.edu")

    get datasets_path, params: { q: "guest-badge-hidden" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("updated:")
    expect(response.body).not_to include("created:")
    expect(response.body).not_to include("ingested:")
    expect(response.body).not_to include("released:")
    expect(response.body).not_to include("version candidate under review")
    expect(response.body).not_to include("has sharing link")
    expect(response.body).to include("published: 2026-01-15")
  end

  it "renders a citation report from search results" do
    dataset = Dataset.create!(
      title: "Report Search Dataset",
      description: "Included in report output",
      keywords: "report-query",
      subject: "Data Science",
      owner_uid: "owner-report-search",
      depositor_name: "Owner Report",
      depositor_email: "owner-report-search@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-0000001"
    )
    dataset.creators.create!(name: "Report Creator")
    dataset.funders.create!(name: "National Science Foundation", grant: "NSF-123")

    get datasets_path, params: { q: "report-query", report: "generate" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Search Citation Report")
    expect(response.body).to include("Go back to search")
    expect(response.body).to include("Query URL:")
    expect(response.body).to include("Report Creator")
    expect(response.body).to include("Report Search Dataset")
    expect(response.body).to include("Funder: National Science Foundation, Grant: NSF-123")
  end

  it "downloads a citation report file from search results" do
    dataset = Dataset.create!(
      title: "Report Download Dataset",
      description: "Included in download output",
      keywords: "download-report-query",
      subject: "Data Science",
      owner_uid: "owner-report-download",
      depositor_name: "Owner Report Download",
      depositor_email: "owner-report-download@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-0000002"
    )
    dataset.creators.create!(name: "Download Creator")

    get datasets_path, params: { q: "download-report-query", report: "generate", download: "now" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.headers["Content-Disposition"]).to include("filename=\"report.txt\"")
    expect(response.body).to include("Illinois Data Bank")
    expect(response.body).to include("Download Creator")
    expect(response.body).to include("Report Download Dataset")
  end
end
