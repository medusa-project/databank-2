require "rails_helper"

RSpec.describe Note, type: :model do
  it "belongs to a dataset" do
    note = described_class.reflect_on_association(:dataset)

    expect(note.macro).to eq(:belongs_to)
  end
end
