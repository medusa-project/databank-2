require "rails_helper"

RSpec.describe "Illinois Experts", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "serves illinois_experts.xml without requiring login" do
    create(
      :dataset,
      publication_state: :published,
      is_test: false,
      org_creators: false,
      identifier: "10.13012/B2IDB-1111111_V1",
      release_date: Date.current,
      title: "Illinois Experts Export"
    )
    allow(IllinoisExpertsClient).to receive(:person_xml_doc).and_return(nil)

    get "/illinois_experts.xml"

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("xml")
    expect(response.body).to include("<v1:datasets")
    expect(response.body).to include("Illinois Experts Export")
  end

  it "requires login for persons endpoint" do
    get "/illinois_experts/persons.xml", params: { email: "person@example.edu" }

    expect(response).to redirect_to(login_path)
  end

  it "allows curator access to persons endpoint" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")
    allow(IllinoisExpertsClient).to receive(:persons).with("person@example.edu").and_return("<person><name>Test Person</name></person>")

    get "/illinois_experts/persons.xml", params: { email: "person@example.edu" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Test Person")
  end

  it "returns missing email error for curator requests without email" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get "/illinois_experts/persons.xml"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("missing email")
  end

  it "blocks non-curator users from persons endpoint" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor User", role: "depositor")

    get "/illinois_experts/persons.xml", params: { email: "person@example.edu" }

    expect(response).to redirect_to(root_path)
  end

  it "returns not found error for example endpoint when client response is blank" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")
    allow(IllinoisExpertsClient).to receive(:example).and_return(nil)

    get "/illinois_experts/example.xml"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("example not found")
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
