require "rails_helper"

RSpec.describe Token, type: :model do
  it "validates required attributes" do
    token = Token.new

    expect(token).not_to be_valid
    expect(token.errors[:dataset_key]).to be_present
    expect(token.errors[:identifier]).to be_present
  end

  it "generates a 32-character token identifier" do
    generated = Token.generate_auth_token

    expect(generated).to match(/\A[0-9a-f]{32}\z/)
  end
end
