require "rails_helper"

RSpec.describe Dataset::IllinoisExpertsExportable, type: :model do
  describe ".to_illinois_experts" do
    it "returns nil when no datasets are eligible for export" do
      create(:dataset, publication_state: :draft)

      expect(Dataset.to_illinois_experts).to be_nil
    end

    it "exports eligible datasets with internal and external creators" do
      dataset = create(
        :dataset,
        publication_state: :published,
        is_test: false,
        org_creators: false,
        title: "Published Dataset",
        description: "Export description",
        identifier: "10.13012/B2IDB-1234567_V1",
        keywords: "earth science; machine learning",
        release_date: Date.new(2024, 2, 3)
      )

      create(
        :creator,
        dataset: dataset,
        email: "internal@illinois.edu",
        given_name: "Internal",
        family_name: "Creator",
        contact: true,
        is_contact: true,
        row_position: 1
      )
      create(
        :creator,
        dataset: dataset,
        email: "external@illinois.edu",
        given_name: "Illinois",
        family_name: "External",
        contact: false,
        is_contact: false,
        row_position: 2
      )
      create(
        :creator,
        dataset: dataset,
        email: "outside@example.org",
        given_name: "Outside",
        family_name: "Creator",
        contact: false,
        is_contact: false,
        row_position: 3
      )
      create(
        :creator,
        dataset: dataset,
        email: " ",
        given_name: "Blank",
        family_name: "Email",
        contact: false,
        is_contact: false,
        row_position: 4
      )

      create(
        :dataset,
        publication_state: :published,
        is_test: true,
        org_creators: false,
        identifier: "10.13012/B2IDB-9999999_V1"
      )

      internal_person_doc = Nokogiri::XML(
        '<person><organisationalUnit uuid="unit-123"/><period><startDate>2021-04-05</startDate></period></person>'
      )

      allow(IllinoisExpertsClient).to receive(:person_xml_doc).and_return(nil)
      allow(IllinoisExpertsClient).to receive(:person_xml_doc).with("internal@illinois.edu").and_return(internal_person_doc)

      xml = Dataset.to_illinois_experts
      expect(xml).to be_present

      doc = Nokogiri::XML(xml)
      namespaces = { "v1" => "v1.dataset.pure.atira.dk", "v3" => "v3.commons.pure.atira.dk" }

      dataset_nodes = doc.xpath("//v1:dataset", namespaces)
      expect(dataset_nodes.count).to eq(1)

      dataset_node = dataset_nodes.first
      expect(dataset_node["id"]).to eq("doi:10.13012/B2IDB-1234567_V1")
      expect(dataset_node.at_xpath("v1:title", namespaces).text).to eq("Published Dataset")
      expect(dataset_node.at_xpath("v1:description", namespaces).text).to eq("Export description")
      expect(dataset_node.at_xpath("v1:DOI", namespaces).text).to eq("10.13012/B2IDB-1234567_V1")

      expect(dataset_node.at_xpath("v1:managingOrganisation", namespaces)["lookupId"])
        .to eq(IdbConfig.fetch(:illinois_experts, :org_id, default: ""))
      expect(dataset_node.at_xpath("v1:publisher", namespaces)["lookupId"])
        .to eq(IdbConfig.fetch(:illinois_experts, :publisher_id, default: ""))

      expect(dataset_node.at_xpath("v1:availableDate/v3:year", namespaces).text).to eq("2024")
      expect(dataset_node.at_xpath("v1:availableDate/v3:month", namespaces).text).to eq("02")
      expect(dataset_node.at_xpath("v1:availableDate/v3:day", namespaces).text).to eq("03")

      keyword_nodes = dataset_node.xpath("v1:keywords/v1:keyword", namespaces)
      expect(keyword_nodes.map(&:text)).to contain_exactly("earth science", "machine learning")

      person_nodes = dataset_node.xpath("v1:persons/v1:person", namespaces)
      expect(person_nodes.count).to eq(3)

      internal_person = dataset_node.at_xpath("v1:persons/v1:person[@id='internal@illinois.edu']", namespaces)
      expect(internal_person).to be_present
      expect(internal_person["contactPerson"]).to eq("true")
      expect(internal_person.at_xpath("v1:person", namespaces)["lookupId"]).to eq("internal@illinois.edu")
      expect(internal_person.at_xpath("v1:organisations/v1:organisation", namespaces)["lookupId"]).to eq("unit-123")
      expect(internal_person.at_xpath("v1:associationStartDate", namespaces).text).to eq("2021-04-05")

      illinois_external = dataset_node.at_xpath("v1:persons/v1:person[@id='external@illinois.edu']", namespaces)
      expect(illinois_external).to be_present
      expect(illinois_external.at_xpath("v1:person", namespaces)["origin"]).to eq("external")
      expect(illinois_external.at_xpath("v1:organisations/v1:organisation", namespaces)["lookupId"])
        .to eq(IdbConfig.fetch(:illinois_experts, :illinois_external_org_id, default: ""))

      external = dataset_node.at_xpath("v1:persons/v1:person[@id='outside@example.org']", namespaces)
      expect(external).to be_present
      expect(external.at_xpath("v1:person", namespaces)["origin"]).to eq("external")
      expect(external.at_xpath("v1:organisations/v1:organisation/v1:name", namespaces).text).to eq("unknown")
    end
  end
end
