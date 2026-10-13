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

  describe "#semantic_action_button" do
    it "renders the secondary semantic action with secondary styling and icon" do
      html = helper.semantic_action_button(action: :secondary, style: :idb)

      expect(html).to include("Secondary")
      expect(html).to include("idb-button-secondary")
      expect(html).to include("fa-minus")
      expect(html).to include('type="button"')
    end

    it "renders a button_to form when url and non-GET method like delete are provided" do
      html = helper.semantic_action_button(action: :delete, url: "/datasets/1/datafiles/2", method: :delete)

      expect(html).to include('<form')
      expect(html).to include('action="/datasets/1/datafiles/2"')
      expect(html).to include('name="_method"')
      expect(html).to include('value="delete"')
    end

    it "renders a link_to anchor when url and GET method are provided" do
      html = helper.semantic_action_button(action: :download, url: "/datasets/1/datafiles/2/download", method: :get)

      expect(html).to include('<a')
      expect(html).to include('href="/datasets/1/datafiles/2/download"')
    end
  end

  describe "#semantic_badge" do
    it "renders a semantic status badge with tone and icon" do
      html = helper.semantic_badge(kind: :status_warning)

      expect(html).to include("idb-badge")
      expect(html).to include("idb-badge--warning")
      expect(html).to include("Warning")
      expect(html).to include("fa-triangle-exclamation")
    end

    it "supports custom labels and accessibility label text" do
      html = helper.semantic_badge(kind: :status_info, label: "Queued", sr_label: "Queued status")

      expect(html).to include("Queued")
      expect(html).to include('aria-label="Queued status"')
      expect(html).to include("sr-only")
    end
  end

  describe "#semantic_count_badge" do
    it "renders a count badge using the count semantic defaults" do
      html = helper.semantic_count_badge(count: 7, sr_label: "Seven items")

      expect(html).to include("idb-badge--info")
      expect(html).to include("7")
      expect(html).to include("fa-hashtag")
      expect(html).to include('aria-label="Seven items"')
    end
  end

  describe "#semantic_status_badge" do
    it "maps failed status values to alert tone" do
      html = helper.semantic_status_badge(status: "failed")

      expect(html).to include("idb-badge--danger")
      expect(html).to include("failed")
    end

    it "maps pending status values to warning tone" do
      html = helper.semantic_status_badge(status: "pending")

      expect(html).to include("idb-badge--warning")
      expect(html).to include("pending")
    end

    it "maps orphaned status values to alert tone" do
      html = helper.semantic_status_badge(status: "orphaned")

      expect(html).to include("idb-badge--danger")
      expect(html).to include("orphaned")
    end

    it "maps available status values to success tone" do
      html = helper.semantic_status_badge(status: "available")

      expect(html).to include("idb-badge--success")
      expect(html).to include("available")
    end

    it "maps not_published status values to neutral tone" do
      html = helper.semantic_status_badge(status: "not_published")

      expect(html).to include("idb-badge--neutral")
      expect(html).to include("not published")
    end
  end
end
