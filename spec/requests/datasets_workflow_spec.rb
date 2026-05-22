require "rails_helper"

RSpec.describe "Datasets workflow", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "allows a depositor to create edit and publish a dataset with contact creator" do
    clear_enqueued_jobs
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Draft Dataset",
        description: "Initial description",
        keywords: "climate,temperature",
        subject: "Environmental Science",
        license: "CC-BY-4.0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    expect(response).to redirect_to(dataset_path(dataset))

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Draft Dataset")

    patch dataset_path(dataset), params: {
      dataset: {
        title: "Updated Dataset",
        description: "Updated description",
        keywords: "climate,temperature,time-series",
        subject: "Earth Systems",
        license: "CC0",
        publisher: "University Library"
      }
    }
    expect(response).to redirect_to(dataset_path(dataset))

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Researcher One",
        email: "researcher@example.edu",
        contact: true,
        position: 1
      }
    }
    expect(response).to redirect_to(edit_dataset_path(dataset))

    csv_fixture = Rails.root.join("test/fixtures/files/analysis.csv")
    uploaded_file = Rack::Test::UploadedFile.new(csv_fixture, "text/csv")

    post dataset_datafiles_path(dataset), params: {
      datafile: {
        binary: uploaded_file,
        description: "Primary analysis file"
      }
    }
    expect(response).to redirect_to(edit_dataset_path(dataset))

    datafile = dataset.datafiles.order(:created_at).last
    expect(datafile.binary).to be_attached
    expect(datafile.binary_name).to eq("analysis.csv")

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
    expect(response.body).to include("column_a,column_b")

    post publish_dataset_path(dataset)

    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    globus_jobs = enqueued_jobs.select { |job| job[:job] == Globus::SubmitDatasetTransferJob }

    expect(ingest_jobs.map { |job| job[:args].first }).to include(dataset.id)
    expect(globus_jobs.map { |job| job[:args].first }).to include(dataset.id)
    expect(response).to redirect_to(dataset_path(dataset))

    dataset.reload
    expect(dataset).to be_published
    expect(dataset.title).to eq("Updated Dataset")
    expect(dataset.keywords).to eq("climate,temperature,time-series")
    expect(dataset.subject).to eq("Earth Systems")
    expect(dataset.license).to eq("CC0")
    expect(dataset.publisher).to eq("University Library")
    expect(dataset.identifier).to eq("10.5555/#{dataset.key}")
  end

  it "downloads using medusa storage metadata without attachment" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Storage-backed Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    datafile = dataset.datafiles.create!(
      web_id: "m3d55",
      binary_name: "remote.csv",
      binary_size: 14,
      storage_root: "medusa",
      storage_key: "path/to/remote.csv"
    )

    allow_any_instance_of(Datafile).to receive(:exists_on_storage?).and_return(true)
    allow_any_instance_of(Datafile).to receive(:with_input_io).and_yield(StringIO.new("a,b\n1,2\n"))

    get download_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="remote.csv"')
    expect(response.body).to include("a,b")
  end

  it "shows the shared legacy funder catalog on the edit form" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Catalog Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    get edit_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("known-funders")
    expect(response.body).to include("U.S. Department of Energy (DOE)")
    expect(response.body).to include("10.13039/100000015")
  end

  it "keeps only one primary contact creator at a time" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Creator Contact Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Creator One",
        email: "one@example.edu",
        contact: true,
        position: 1
      }
    }
    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Creator Two",
        email: "two@example.edu",
        contact: false,
        position: 2
      }
    }

    second_creator = dataset.creators.find_by!(name: "Creator Two")

    patch dataset_creator_path(dataset, second_creator), params: {
      creator: {
        name: "Creator Two",
        email: "two@example.edu",
        contact: true,
        position: 2
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(dataset.creators.find_by!(name: "Creator One").reload.contact).to be(false)
    expect(second_creator.reload.contact).to be(true)
  end

  it "blocks publish until every creator has an email address" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Creator Email Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Creator One",
        email: "one@example.edu",
        contact: true,
        position: 1
      }
    }
    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Creator Two",
        email: "",
        contact: false,
        position: 2
      }
    }

    csv_fixture = Rails.root.join("test/fixtures/files/analysis.csv")
    uploaded_file = Rack::Test::UploadedFile.new(csv_fixture, "text/csv")

    post dataset_datafiles_path(dataset), params: {
      datafile: {
        binary: uploaded_file,
        description: "Primary analysis file"
      }
    }

    post publish_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Cannot publish: email address for all creators required.")
    expect(dataset.reload).to be_draft
  end

  it "shows richer public metadata while keeping depositor details private" do
    dataset = Dataset.create!(
      title: "Public Metadata Dataset",
      description: "A fully described dataset.",
      keywords: "climate,public",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-public",
      depositor_name: "Depositor Private",
      depositor_email: "private@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-1234567"
    )
    dataset.creators.create!(name: "Researcher One", email: "researcher@example.edu", contact: true, position: 1)
    dataset.contributors.create!(name: "Research Support", email: "support@example.edu", role: "Data Curator", position: 1)
    dataset.funders.create!(name: "U.S. Department of Energy (DOE)", identifier: "10.13039/100000015", award_number: "DE-12345", position: 1)
    dataset.related_materials.create!(title: "Project Article", uri: "https://example.org/article", relation_type: "IsSupplementTo", position: 1)
    dataset.datafiles.create!(binary_name: "analysis.csv", binary_size: 1024, description: "Tabular output")

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Persistent URL")
    expect(response.body).to include("https://doi.org/10.5555/IDB-1234567")
    expect(response.body).to include("Contributors")
    expect(response.body).to include("Funders")
    expect(response.body).to include("Related Materials")
    expect(response.body).to include("Project Article")
    expect(response.body).to include("Tabular output")
    expect(response.body).not_to include("Depositor Private")
    expect(response.body).not_to include("researcher@example.edu")
    expect(response.body).not_to include("support@example.edu")
  end

  it "shows depositor details to admins on the dataset page" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    dataset = Dataset.create!(
      title: "Admin Metadata Dataset",
      description: "A fully described dataset.",
      keywords: "climate,admin",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-admin",
      depositor_name: "Depositor Private",
      depositor_email: "private@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-7654321"
    )
    dataset.creators.create!(name: "Researcher One", email: "researcher@example.edu", contact: true, position: 1)

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Depositor")
    expect(response.body).to include("Depositor Private")
    expect(response.body).to include("private@example.edu")
    expect(response.body).to include("researcher@example.edu")
  end

  it "rejects related materials with a URI but no relation type" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Related Material Validation Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    post dataset_related_materials_path(dataset), params: {
      related_material: {
        title: "Project Article",
        uri: "https://example.org/article",
        relation_type: "",
        position: 1
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Relation type can't be blank")
    expect(dataset.related_materials).to be_empty
  end

  it "blocks publish when a related material URI is missing a relation type" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Publish Related Material Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Creator One",
        email: "one@example.edu",
        contact: true,
        position: 1
      }
    }

    dataset.related_materials.create!(title: "Draft Note", position: 1)
    dataset.related_materials.update_all(uri: "https://example.org/article", relation_type: nil)

    csv_fixture = Rails.root.join("test/fixtures/files/analysis.csv")
    uploaded_file = Rack::Test::UploadedFile.new(csv_fixture, "text/csv")

    post dataset_datafiles_path(dataset), params: {
      datafile: {
        binary: uploaded_file,
        description: "Primary analysis file"
      }
    }

    post publish_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Cannot publish: relation type for each related material URI required.")
    expect(dataset.reload).to be_draft
  end

  it "creates a new draft version from a published dataset and preserves lineage" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    previous = Dataset.create!(
      title: "Versioned Dataset",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-2222222"
    )
    previous.creators.create!(name: "Researcher One", email: "researcher@example.edu", contact: true, position: 1)
    previous.contributors.create!(name: "Research Support", email: "support@example.edu", role: "Data Curator", position: 1)
    previous.funders.create!(name: "U.S. Department of Energy (DOE)", identifier: "10.13039/100000015", award_number: "DE-12345", position: 1)
    previous.related_materials.create!(title: "Project Article", uri: "https://example.org/article", relation_type: "IsSupplementTo", position: 1)

    post version_dataset_path(previous)

    new_dataset = Dataset.order(:created_at).last

    expect(response).to redirect_to(edit_dataset_path(new_dataset))
    expect(new_dataset).to be_draft
    expect(new_dataset.identifier).to be_nil
    expect(new_dataset.title).to eq(previous.title)
    expect(new_dataset.description).to eq(previous.description)
    expect(new_dataset.creators.pluck(:name)).to eq([ "Researcher One" ])
    expect(new_dataset.contributors.pluck(:name)).to eq([ "Research Support" ])
    expect(new_dataset.funders.pluck(:name)).to eq([ "U.S. Department of Energy (DOE)" ])
    expect(new_dataset.related_materials.find_by!(relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION).uri).to eq("https://doi.org/10.5555/IDB-2222222")
    expect(new_dataset.related_materials.find_by!(title: "Project Article").relation_type).to eq("IsSupplementTo")

    next_version_link = previous.related_materials.find_by!(relation_type: RelatedMaterial::VERSION_NEW_RELATION)
    expect(next_version_link.uri).to include("/datasets/#{new_dataset.key}")

    get dataset_path(previous)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version Lineage")
    expect(response.body).to include("Next Version")
    expect(response.body).to include(new_dataset.key)

    get dataset_path(new_dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version Lineage")
    expect(response.body).to include("Previous Version")
    expect(response.body).to include(previous.key)
  end

  it "blocks version creation for a depositor who does not own the dataset" do
    source = Dataset.create!(
      title: "Owned Version Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-1122334"
    )

    sign_in_as(email: "other@example.edu", name: "Other Depositor", role: "depositor")

    expect {
      post version_dataset_path(source)
    }.not_to change(Dataset, :count)

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  it "blocks version creation for datasets that are not published" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Draft Version Source",
      description: "Draft source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )

    expect {
      post version_dataset_path(source)
    }.not_to change(Dataset, :count)

    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("Only published datasets can be versioned.")
  end

  it "blocks version creation when a newer published version is already linked" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Source With Existing Successor",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-5566778"
    )

    existing_successor = Dataset.create!(
      title: "Existing Successor",
      description: "Already-started successor version.",
      keywords: "v2",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-5566779"
    )
    existing_successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    expect {
      post version_dataset_path(source)
    }.not_to change(Dataset, :count)

    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("A newer version has already been started for this dataset.")
  end

  it "allows version creation when only a draft successor exists" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Source With Draft Successor",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-5566780"
    )

    draft_successor = Dataset.create!(
      title: "Draft Successor",
      description: "Draft successor version.",
      keywords: "v2",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    draft_successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    expect {
      post version_dataset_path(source)
    }.to change(Dataset, :count).by(1)

    new_dataset = Dataset.order(:created_at).last
    expect(response).to redirect_to(edit_dataset_path(new_dataset))
    expect(new_dataset).to be_draft
  end

  it "returns a safe alert when create_version fails unexpectedly" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Source for Create Version Failure",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-6600118"
    )

    allow_any_instance_of(DatasetVersionBuilder).to receive(:call).and_raise(StandardError, "boom")

    post version_dataset_path(source)

    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("Could not create a new version right now. Please try again.")
    expect(response.body).not_to include("boom")
  end

  it "surfaces ArgumentError message when create_version raises ArgumentError" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Source for Create Version ArgumentError",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-6610118"
    )

    allow_any_instance_of(DatasetVersionBuilder).to receive(:call).and_raise(ArgumentError, "previous dataset must be published")

    post version_dataset_path(source)

    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("previous dataset must be published")
  end

  it "shows the Request New Version button for an eligible owner" do
    source = Dataset.create!(
      title: "Eligible Version Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900112"
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Request New Version")
  end

  it "hides the Request New Version button when a published successor version already exists" do
    source = Dataset.create!(
      title: "Source Hidden Version Button",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900113"
    )

    successor = Dataset.create!(
      title: "Existing Successor for Hidden Button",
      description: "Draft successor.",
      keywords: "v2",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900213"
    )
    successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Request New Version")
  end

  it "shows the Request New Version button when only a draft successor exists" do
    source = Dataset.create!(
      title: "Source With Draft Successor Button",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900214"
    )

    successor = Dataset.create!(
      title: "Draft Successor for Visible Button",
      description: "Draft successor.",
      keywords: "v2",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Request New Version")
  end

  it "hides the Request New Version button for a non-owner depositor" do
    source = Dataset.create!(
      title: "Eligible Source Hidden For Non-Owner",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900114"
    )

    sign_in_as(email: "other@example.edu", name: "Other Depositor", role: "depositor")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Request New Version")
  end

  it "lets a depositor submit a version request and shows acknowledgement" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Request Flow Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900310"
    )

    get pre_version_dataset_path(source)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Information before requesting a new version")

    expect {
      post submit_version_request_dataset_path(source), params: { comment: "Need to add corrected analysis files." }
    }.to change(VersionRequest, :count).by(1)

    request = VersionRequest.order(:created_at).last
    expect(response).to redirect_to(version_acknowledge_dataset_path(source, version_request_id: request.id))

    follow_redirect!
    expect(response.body).to include("Your new version request has been submitted")
    expect(response.body).to include("Need to add corrected analysis files.")

    expect(request.status).to eq("pending")
    expect(request.requester_email).to eq("owner@example.edu")
  end

  it "does not create a duplicate pending version request" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Duplicate Request Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900318"
    )

    existing_request = source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Already pending",
      requested_at: Time.current,
      status: :pending
    )

    expect {
      post submit_version_request_dataset_path(source), params: { comment: "Second request attempt" }
    }.not_to change(VersionRequest, :count)

    expect(response).to redirect_to(version_acknowledge_dataset_path(source, version_request_id: existing_request.id))
    follow_redirect!
    expect(response.body).to include("Current status:")
    expect(response.body).to include("Pending")
  end

  it "shows acknowledgement only for pending version requests" do
    source = Dataset.create!(
      title: "Acknowledgement Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900320"
    )

    pending_request = source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Pending acknowledgement request",
      requested_at: Time.current,
      status: :pending
    )

    approved_request = source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Approved request",
      requested_at: Time.current,
      status: :approved,
      reviewed_at: Time.current,
      reviewed_by_uid: "admin@example.edu"
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    get version_acknowledge_dataset_path(source, version_request_id: pending_request.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your new version request has been submitted")

    get version_acknowledge_dataset_path(source, version_request_id: approved_request.id)
    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("No pending version request found.")
  end

  it "redirects when acknowledgement request id is missing" do
    source = Dataset.create!(
      title: "Missing Ack Request Id Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900321"
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    get version_acknowledge_dataset_path(source)

    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("No pending version request found.")
  end

  it "allows an admin to approve a pending version request and create a draft" do
    source = Dataset.create!(
      title: "Admin Approval Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900311"
    )

    request = source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Need a corrected v2",
      requested_at: Time.current,
      status: :pending
    )

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect {
      post approve_version_request_dataset_path(source, version_request_id: request.id), params: { review_note: "Approved for update" }
    }.to change(Dataset, :count).by(1)

    new_dataset = Dataset.order(:created_at).last
    expect(response).to redirect_to(edit_dataset_path(new_dataset))

    request.reload
    expect(request.status).to eq("approved")
    expect(request.reviewed_by_uid).to eq("admin@example.edu")
    expect(request.approved_dataset_id).to eq(new_dataset.id)
  end

  it "allows an admin to reject a pending version request" do
    source = Dataset.create!(
      title: "Admin Rejection Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900315"
    )

    request = source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Need correction",
      requested_at: Time.current,
      status: :pending
    )

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect {
      post reject_version_request_dataset_path(source, version_request_id: request.id), params: { review_note: "Needs additional detail" }
    }.not_to change(Dataset, :count)

    expect(response).to redirect_to(dataset_path(source))

    request.reload
    expect(request.status).to eq("rejected")
    expect(request.reviewed_by_uid).to eq("admin@example.edu")
    expect(request.review_note).to eq("Needs additional detail")
    expect(request.approved_dataset_id).to be_nil
  end

  it "shows optional curator review note fields on pending requests for admins" do
    source = Dataset.create!(
      title: "Admin Pending Queue Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900319"
    )

    source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Pending request for admin queue",
      requested_at: Time.current,
      status: :pending
    )

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pending Version Requests")
    expect(response.body).to include("Curator review note (optional)")
    expect(response.body).to include("Approve and Create Draft")
    expect(response.body).to include("Reject Request")
  end

  it "blocks non-admin approval of a version request" do
    source = Dataset.create!(
      title: "Unauthorized Approval Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900312"
    )

    request = source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Need a corrected v2",
      requested_at: Time.current,
      status: :pending
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    expect {
      post approve_version_request_dataset_path(source, version_request_id: request.id)
    }.not_to change(Dataset, :count)

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  it "does not allow version request submission when dataset is ineligible" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Ineligible Request Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900313"
    )

    successor = Dataset.create!(
      title: "Existing Published Successor",
      description: "Published successor dataset.",
      keywords: "v2",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900314"
    )
    successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    expect {
      post submit_version_request_dataset_path(source), params: { comment: "Please allow new version." }
    }.not_to change(VersionRequest, :count)

    expect(response).to redirect_to(dataset_path(source))
    follow_redirect!
    expect(response.body).to include("A newer version has already been started for this dataset.")
  end

  it "shows version request history to the dataset owner" do
    source = Dataset.create!(
      title: "Owner Request History Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900316"
    )

    source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Pending update request",
      requested_at: 2.days.ago,
      status: :pending
    )
    source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Rejected update request",
      requested_at: 1.day.ago,
      status: :rejected,
      reviewed_at: Time.current,
      reviewed_by_uid: "admin@example.edu",
      review_note: "Please include detailed change scope"
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version Request History")
    expect(response.body).to include("Pending request from Owner User")
    expect(response.body).to include("Rejected request from Owner User")
    expect(response.body).to include("Please include detailed change scope")
  end

  it "hides version request history from non-owners" do
    source = Dataset.create!(
      title: "Private Request History Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900317"
    )

    source.version_requests.create!(
      requester_uid: "owner@example.edu",
      requester_email: "owner@example.edu",
      requester_name: "Owner User",
      comment: "Pending private request",
      requested_at: Time.current,
      status: :pending
    )

    sign_in_as(email: "other@example.edu", name: "Other Depositor", role: "depositor")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Version Request History")
    expect(response.body).not_to include("Pending private request")
  end

  it "allows an admin to create a new version for another depositor's published dataset" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    source = Dataset.create!(
      title: "Admin Version Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900115"
    )

    expect {
      post version_dataset_path(source)
    }.to change(Dataset, :count).by(1)

    new_dataset = Dataset.order(:created_at).last
    expect(response).to redirect_to(edit_dataset_path(new_dataset))
    expect(new_dataset).to be_draft
  end

  it "shows the Create New Version button to admins when dataset is eligible" do
    source = Dataset.create!(
      title: "Admin Eligible Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900116"
    )

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create New Version")
  end

  it "hides the Create New Version button from admins when a published successor makes dataset ineligible" do
    source = Dataset.create!(
      title: "Admin Ineligible Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900117"
    )

    successor = Dataset.create!(
      title: "Existing Admin Successor",
      description: "Draft successor.",
      keywords: "v2",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900217"
    )
    successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Create New Version")
  end

  it "copies files from previous version into a draft version dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    previous = Dataset.create!(
      title: "Source for File Copy",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900118"
    )

    csv_fixture = Rails.root.join("test/fixtures/files/analysis.csv")
    attached = previous.datafiles.create!(description: "Attached source")
    attached.binary.attach(io: File.open(csv_fixture), filename: "analysis.csv", content_type: "text/csv")
    attached.sync_metadata_from_attachment!
    attached.save!
    previous.datafiles.create!(
      binary_name: "remote.csv",
      binary_size: 64,
      description: "Storage source",
      storage_root: "medusa",
      storage_key: "path/to/remote.csv"
    )

    post version_dataset_path(previous)
    version = Dataset.order(:created_at).last

    expect(response).to redirect_to(edit_dataset_path(version))
    get edit_dataset_path(version)
    expect(response.body).to include("Copy Files from Previous Version")
    expect(response.body).to include("Version Lineage")
    expect(response.body).to include("Previous Version")
    expect(response.body).to include(previous.key)

    post copy_version_files_dataset_path(version)

    expect(response).to redirect_to(edit_dataset_path(version))
    follow_redirect!
    expect(response.body).to include("Copied 2 file(s) from the previous version")

    version.reload
    expect(version.datafiles.count).to eq(2)
    expect(version.datafiles.find_by!(binary_name: "analysis.csv").binary).to be_attached
    expect(version.datafiles.find_by!(storage_key: "path/to/remote.csv").binary_name).to eq("remote.csv")

    post copy_version_files_dataset_path(version)
    follow_redirect!
    expect(response.body).to include("skipped 2 duplicate(s)")
    expect(version.reload.datafiles.count).to eq(2)
  end

  it "blocks copy_version_files for a non-owner depositor" do
    previous = Dataset.create!(
      title: "Source for Unauthorized Copy",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-4400118"
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    post version_dataset_path(previous)
    version = Dataset.order(:created_at).last

    sign_in_as(email: "other@example.edu", name: "Other Depositor", role: "depositor")

    post copy_version_files_dataset_path(version)

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  it "rejects copy_version_files when target dataset is published" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    dataset = Dataset.create!(
      title: "Published Target",
      description: "Published dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-5500118"
    )

    post copy_version_files_dataset_path(dataset)

    expect(response).to redirect_to(edit_dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Version files can only be copied into a draft dataset.")
  end

  it "rejects copy_version_files when previous version dataset cannot be resolved" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    version = Dataset.create!(
      title: "Draft With Unresolvable Previous",
      description: "Draft dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    version.related_materials.create!(
      title: "Unknown Previous",
      uri: "https://doi.org/10.5555/IDB-UNRESOLVABLE",
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    post copy_version_files_dataset_path(version)

    expect(response).to redirect_to(edit_dataset_path(version))
    follow_redirect!
    expect(response.body).to include("No previous version dataset found to copy files from.")
  end

  it "returns a safe alert when copy_version_files fails unexpectedly" do
    previous = Dataset.create!(
      title: "Source for Failure Case",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-7700118"
    )

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    post version_dataset_path(previous)
    version = Dataset.order(:created_at).last

    allow_any_instance_of(DatasetVersionFileCopyService).to receive(:call).and_raise(StandardError, "boom")

    post copy_version_files_dataset_path(version)

    expect(response).to redirect_to(edit_dataset_path(version))
    follow_redirect!
    expect(response.body).to include("Could not copy files from the previous version. Please try again.")
    expect(response.body).not_to include("boom")
  end

  it "does not show copy files button on non-version drafts" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    dataset = Dataset.create!(
      title: "Regular Draft",
      description: "Draft without previous relation.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )

    get edit_dataset_path(dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Copy Files from Previous Version")
    expect(response.body).not_to include("Version Lineage")
  end

  it "shows external previous-version URI fallback on edit page when local dataset is unavailable" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    version = Dataset.create!(
      title: "Version With External Previous URI",
      description: "Draft with external lineage only.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    version.related_materials.create!(
      title: "Legacy Published Dataset",
      uri: "https://doi.org/10.5555/IDB-DOES-NOT-EXIST",
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    get edit_dataset_path(version)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version Lineage")
    expect(response.body).to include("Previous Version")
    expect(response.body).to include("Legacy Published Dataset")
    expect(response.body).to include("https://doi.org/10.5555/IDB-DOES-NOT-EXIST")
  end

  it "shows external next-version URI fallback on show and edit pages when local successor is unavailable" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    dataset = Dataset.create!(
      title: "Dataset With External Next URI",
      description: "Published dataset with external successor link.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-3030303"
    )
    dataset.related_materials.create!(
      title: "External Successor Dataset",
      uri: "https://doi.org/10.5555/IDB-NEXT-ONLY",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    get dataset_path(dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version Lineage")
    expect(response.body).to include("Next Version")
    expect(response.body).to include("External Successor Dataset")
    expect(response.body).to include("https://doi.org/10.5555/IDB-NEXT-ONLY")

    get edit_dataset_path(dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version Lineage")
    expect(response.body).to include("Next Version")
    expect(response.body).to include("External Successor Dataset")
    expect(response.body).to include("https://doi.org/10.5555/IDB-NEXT-ONLY")
  end

  it "does not expose draft successor details to guests on published source pages" do
    source = Dataset.create!(
      title: "Public Source With Draft Successor",
      description: "Published dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9090909"
    )

    draft_successor = Dataset.create!(
      title: "Hidden Draft Successor",
      description: "Draft successor.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    draft_successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Version Lineage")
    expect(response.body).not_to include("Hidden Draft Successor")
    expect(response.body).not_to include(draft_successor.key)
  end

  it "shows versions panel with published entries for guests and includes newer-version banner" do
    source = Dataset.create!(
      title: "Guest Versions Source",
      description: "Published dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-8000001"
    )

    newer = Dataset.create!(
      title: "Guest Versions Newer",
      description: "Published successor.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-8000002"
    )
    newer.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )

    draft_successor = Dataset.create!(
      title: "Guest Versions Draft",
      description: "Draft successor.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    source.related_materials.create!(
      title: draft_successor.title,
      uri: "https://example.test/datasets/#{draft_successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 2
    )

    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A newer version of this dataset is available.")
    expect(response.body).to include("Versions in Illinois Data Bank")
    expect(response.body).to include("Guest Versions Newer")
    expect(response.body).not_to include("Guest Versions Draft")
  end

  it "hides draft entries in versions panel from owners" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    source = Dataset.create!(
      title: "Owner Versions Source",
      description: "Published dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-8100001"
    )

    draft_successor = Dataset.create!(
      title: "Owner Versions Draft",
      description: "Draft successor.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    source.related_materials.create!(
      title: draft_successor.title,
      uri: "https://example.test/datasets/#{draft_successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Versions in Illinois Data Bank")
  end

  it "shows draft entries in versions panel to admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    source = Dataset.create!(
      title: "Admin Versions Source",
      description: "Published dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-8100002"
    )

    draft_successor = Dataset.create!(
      title: "Admin Versions Draft",
      description: "Draft successor.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    source.related_materials.create!(
      title: draft_successor.title,
      uri: "https://example.test/datasets/#{draft_successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Versions in Illinois Data Bank")
    expect(response.body).to include("Admin Versions Draft")
  end

  it "links newer-version banner to latest published version through an intermediate draft" do
    source = Dataset.create!(
      title: "Mixed Chain Source",
      description: "Published dataset.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-8300001"
    )

    draft_successor = Dataset.create!(
      title: "Mixed Chain Draft",
      description: "Draft successor.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
    source.related_materials.create!(
      title: draft_successor.title,
      uri: "https://example.test/datasets/#{draft_successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    newest_published = Dataset.create!(
      title: "Mixed Chain Latest",
      description: "Published successor beyond draft.",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-8300002"
    )
    draft_successor.related_materials.create!(
      title: newest_published.title,
      uri: "https://example.test/datasets/#{newest_published.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    get dataset_path(source)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A newer version of this dataset is available.")
    expect(response.body).to include(%(href="/datasets/#{newest_published.key}"))
    expect(response.body).not_to include(%(href="/datasets/#{draft_successor.key}"))
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        nickname: email,
        role: role
      }
    )

    get "/auth/developer/callback"
    expect(response).to have_http_status(:redirect)
  end
end
