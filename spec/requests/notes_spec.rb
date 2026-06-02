require "rails_helper"

RSpec.describe "Curator notes", type: :request do
  let(:dataset) do
    Dataset.create!(
      title: "Curator note target",
      description: "Dataset used for curator notes tests",
      owner_uid: "owner-123",
      depositor_name: "Depositor Name",
      depositor_email: "depositor@example.test"
    )
  end

  def sign_in_as(email:, role:)
    post "/auth/developer/callback", params: {
      email: email,
      name: email.split("@").first,
      role: role
    }
  end

  it "allows a curator to create, edit, view, and delete notes" do
    sign_in_as(email: "curator@example.test", role: "curator")

    get dataset_notes_path(dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New Note")

    post dataset_notes_path(dataset), params: {
      note: {
        body: "Needs metadata review",
        author: "curator@example.test"
      }
    }

    note = dataset.notes.order(:created_at).last
    expect(response).to redirect_to(dataset_notes_path(dataset))
    follow_redirect!
    expect(response.body).to include("Note was successfully created.")
    expect(response.body).to include("Needs metadata review")

    get dataset_note_path(dataset, note)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("curator@example.test")

    patch dataset_note_path(dataset, note), params: {
      note: {
        body: "Review complete",
        author: "curator@example.test"
      }
    }

    expect(response).to redirect_to(dataset_notes_path(dataset))
    follow_redirect!
    expect(response.body).to include("Note was successfully updated.")
    expect(response.body).to include("Review complete")

    delete dataset_note_path(dataset, note)
    expect(response).to redirect_to(dataset_notes_path(dataset))
    follow_redirect!
    expect(response.body).to include("Note was successfully deleted.")
    expect(response.body).not_to include("Review complete")
  end

  it "blocks a depositor from accessing curator notes" do
    sign_in_as(email: dataset.depositor_email, role: "depositor")

    get dataset_notes_path(dataset)

    expect(response).to redirect_to(root_path)
  end
end
