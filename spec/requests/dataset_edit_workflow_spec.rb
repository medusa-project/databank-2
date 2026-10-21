require "rails_helper"

RSpec.describe "Dataset edit workflow actions", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let(:dataset) do
    Dataset.create!(
      title: "Workflow dataset",
      description: "Dataset for edit workflow tests",
      owner_uid: "owner-workflow-1",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu"
    )
  end

  it "redirects to index when save and exit is requested" do
    sign_in_as(email: dataset.depositor_email, name: "Owner User", role: "depositor")

    patch dataset_path(dataset), params: {
      dataset: { title: "Workflow dataset updated" },
      save_and_exit: "true"
    }

    expect(response).to redirect_to(datasets_path)
    follow_redirect!
    expect(response.body).to include("Dataset updated and saved.")
  end

  it "renders native submit buttons associated with the draft metadata form" do
    sign_in_as(email: dataset.depositor_email, name: "Owner User", role: "depositor")

    get edit_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML5(response.body)
    buttons = document.css("button[type='submit'][form='dataset-edit-form']")
    expect(buttons.map { |button| button.text.strip }).to include("Save & Continue", "Save & Exit")
    exit_button = buttons.find { |button| button["name"] == "save_and_exit" }
    expect(exit_button["value"]).to eq("true")
    delete_form = document.at_css("#dataset-delete-form")
    expect(delete_form.ancestors("form")).to be_empty
    expect(delete_form["action"]).to eq(dataset_path(dataset))
    expect(delete_form.at_css("input[name='_method']")["value"]).to eq("delete")
    expect(document.at_css("button[type='submit'][form='dataset-delete-form']").text.strip).to eq("Delete")
  end

  it "renders Confirm as a native submit button for published metadata" do
    dataset.update!(publication_state: :published)
    sign_in_as(email: dataset.depositor_email, name: "Owner User", role: "depositor")

    get edit_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML5(response.body)
    buttons = document.css("button[type='submit'][form='dataset-edit-form']")
    expect(buttons.map { |button| button.text.strip }).to include("Confirm")
  end

  it "renders independent action forms without breaking the metadata form" do
    sign_in_as(email: "admin-workflow@example.edu", name: "Admin User", role: "admin")
    grant = dataset.dataset_access_grants.create!(email: "reviewer@example.edu", access_level: :viewer)
    create_list(:datafile, 2, dataset: dataset, attach_binary: false)

    get edit_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML5(response.body)
    edit_form = document.at_css("#dataset-edit-form")
    expect(edit_form.css("form")).to be_empty
    expect(edit_form.at_css("#dataset_description")).to be_present
    expect(edit_form.at_css("#funder-rows")).to be_present
    expect(edit_form.at_css("#material-rows")).to be_present
    expect(document.at_css("#dataset-access-grant-form")["action"]).to eq(dataset_dataset_access_grants_path(dataset))
    expect(document.at_css("#dataset_access_grant_email")["form"]).to eq("dataset-access-grant-form")
    expect(document.at_css("#dataset-access-grant-remove-#{grant.id}")["action"]).to eq(dataset_dataset_access_grant_path(dataset, grant))
    expect(document.at_css("#bulk-file-delete-form")["action"]).to eq(bulk_destroy_dataset_datafiles_path(dataset))
    expect(document.css('input[name="selected_files[]"]').map { |input| input["form"] }).to eq(
      [ "bulk-file-delete-form", "bulk-file-delete-form" ]
    )
    dataset.datafiles.each do |datafile|
      expect(document.at_css("#datafile-delete-#{datafile.id}")["action"]).to eq(dataset_datafile_path(dataset, datafile))
      expect(edit_form.at_css("button[form='datafile-delete-#{datafile.id}']")).to be_present
    end
    expect(document.css('form').all? { |form| form.ancestors("form").empty? }).to be(true)
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
