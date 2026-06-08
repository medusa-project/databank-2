require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#external_https_link_to" do
    it "renders a link for https urls" do
      html = helper.external_https_link_to(label: "Illinois", url: "https://www.illinois.edu", class: "external-link")

      expect(html).to include('href="https://www.illinois.edu"')
      expect(html).to include("Illinois")
      expect(html).to include('class="external-link"')
    end

    it "renders a link for http urls" do
      html = helper.external_https_link_to(label: "Example", url: "http://example.edu")

      expect(html).to include('href="http://example.edu"')
    end

    it "returns nil for blank, invalid, or non-http urls" do
      expect(helper.external_https_link_to(label: "Blank", url: nil)).to be_nil
      expect(helper.external_https_link_to(label: "FTP", url: "ftp://example.edu/file.txt")).to be_nil
      expect(helper.external_https_link_to(label: "Relative", url: "/local/path")).to be_nil
      expect(helper.external_https_link_to(label: "Broken", url: "http://exa mple.edu")).to be_nil
    end
  end

  describe "#dataset_persistent_url" do
    it "returns the DOI URL when the dataset has an identifier" do
      dataset = build(:dataset, identifier: "10.5555/example-doi")

      expect(helper.dataset_persistent_url(dataset)).to eq("https://doi.org/10.5555/example-doi")
    end

    it "returns nil when the dataset identifier is blank" do
      dataset = build(:dataset, identifier: nil)

      expect(helper.dataset_persistent_url(dataset)).to be_nil
    end
  end

  describe "#dataset_plain_text_citation" do
    it "builds a citation with creators, year, title, publisher, and DOI URL" do
      dataset = build(
        :dataset,
        title: "Citation Dataset",
        publisher: "Illinois Data Bank",
        identifier: "10.5555/citation-dataset",
        published_at: Time.zone.parse("2024-03-01 12:00:00")
      )
      dataset.creators.build(name: "Ada Lovelace")
      dataset.creators.build(name: "Grace Hopper")

      citation = helper.dataset_plain_text_citation(dataset)

      expect(citation).to eq("Ada Lovelace; Grace Hopper (2024) Citation Dataset. Illinois Data Bank https://doi.org/10.5555/citation-dataset")
    end

    it "falls back from published_at to updated_at and omits blank parts" do
      dataset = build(:dataset, title: nil, publisher: nil, identifier: nil, published_at: nil)
      dataset.updated_at = Time.zone.parse("2025-05-15 09:00:00")
      dataset.creators.build(name: "Primary Creator")
      dataset.creators.build(name: "")

      expect(helper.dataset_plain_text_citation(dataset)).to eq("Primary Creator (2025)")
    end

    it "falls back to created_at when published_at and updated_at are unavailable" do
      dataset = build(:dataset, title: "Created Citation", publisher: nil, identifier: nil, published_at: nil)
      dataset.updated_at = nil
      dataset.created_at = Time.zone.parse("2023-01-10 08:30:00")

      expect(helper.dataset_plain_text_citation(dataset)).to eq("(2023) Created Citation.")
    end
  end

  describe "#dataset_primary_contact_name" do
    it "returns the name of the first contact creator" do
      dataset = build(:dataset)
      dataset.creators.build(name: "Secondary Creator", contact: false)
      dataset.creators.build(name: "Primary Contact", contact: true)

      expect(helper.dataset_primary_contact_name(dataset)).to eq("Primary Contact")
    end

    it "returns nil when no contact creator is present" do
      dataset = build(:dataset)
      dataset.creators.build(name: "Only Creator", contact: false)

      expect(helper.dataset_primary_contact_name(dataset)).to be_nil
    end
  end
end
