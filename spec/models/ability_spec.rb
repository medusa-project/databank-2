require "rails_helper"

RSpec.describe Ability do
  it "does not allow an anonymous user to create datasets" do
    ability = described_class.new(nil)

    expect(ability.can?(:create, Dataset)).to be(false)
  end

  it "allows a depositor to create datasets" do
    user = create(:user, role: "depositor")
    ability = described_class.new(user)

    expect(ability.can?(:create, Dataset)).to be(true)
  end
end
