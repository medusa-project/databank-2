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

  it "blocks version creation when a newer version is already linked" do
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
      publication_state: :draft
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

  it "shows the Create New Version button only for an eligible owner" do
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
    expect(response.body).to include("Create New Version")
  end

  it "hides the Create New Version button when a successor version already exists" do
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
    expect(response.body).not_to include("Create New Version")
  end

  it "hides the Create New Version button for a non-owner depositor" do
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
    expect(response.body).not_to include("Create New Version")
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

  it "hides the Create New Version button from admins when dataset is ineligible" do
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
      publication_state: :draft
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
