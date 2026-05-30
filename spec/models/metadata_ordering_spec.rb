require "rails_helper"

RSpec.describe "Metadata ordering parity", type: :model do
  let(:dataset) { create(:dataset) }

  it "copies position into row_position for creators" do
    creator = dataset.creators.create!(name: "Creator A", position: 3, row_position: nil)

    expect(creator.reload.row_position).to eq(3)
  end

  it "copies position into row_position for contributors" do
    contributor = dataset.contributors.create!(name: "Contributor A", role: "Analyst", position: 4, row_position: nil)

    expect(contributor.reload.row_position).to eq(4)
  end

  it "copies position into row_position for related materials" do
    material = dataset.related_materials.create!(title: "Material A", position: 5, row_position: nil)

    expect(material.reload.row_position).to eq(5)
  end

  it "orders creators by coalesced row_position and position" do
    dataset.creators.create!(name: "Creator Third", position: 3, row_position: nil)
    dataset.creators.create!(name: "Creator First", position: 99, row_position: 1)
    dataset.creators.create!(name: "Creator Second", position: nil, row_position: 2)

    expect(dataset.reload.creators.pluck(:name)).to eq([
      "Creator First",
      "Creator Second",
      "Creator Third"
    ])
  end

  it "orders related materials by coalesced row_position and position" do
    dataset.related_materials.create!(title: "Material Third", position: 3, row_position: nil)
    dataset.related_materials.create!(title: "Material First", position: 99, row_position: 1)
    dataset.related_materials.create!(title: "Material Second", position: nil, row_position: 2)

    expect(dataset.reload.related_materials.pluck(:title)).to eq([
      "Material First",
      "Material Second",
      "Material Third"
    ])
  end
end
