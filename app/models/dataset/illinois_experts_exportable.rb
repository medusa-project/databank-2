# frozen_string_literal: true

module Dataset::IllinoisExpertsExportable
  extend ActiveSupport::Concern

  class_methods do
    def to_illinois_experts
      datasets = Dataset.where(is_test: false, org_creators: false).select(&:publicly_readable_now?)
      return nil unless datasets.any?

      root_string = '<v1:datasets xmlns:v1="v1.dataset.pure.atira.dk" xmlns:v3="v3.commons.pure.atira.dk"></v1:datasets>'
      doc = Nokogiri::XML::Document.parse(root_string)
      datasets_node = doc.first_element_child
      exported_count = 0

      datasets.each do |dataset|
        next if dataset.identifier.blank?

        dataset_release_date = dataset.release_date || Time.zone.today

        dataset_node = doc.create_element("v1:dataset")
        dataset_node["id"] = "doi:#{dataset.identifier}"
        dataset_node["type"] = "dataset"
        dataset_node.parent = datasets_node

        title_node = doc.create_element("v1:title")
        title_node.content = dataset.title.to_s
        title_node.parent = dataset_node

        managing_org_node = doc.create_element("v1:managingOrganisation")
        managing_org_node["lookupId"] = IdbConfig.fetch(:illinois_experts, :org_id, default: "").to_s
        managing_org_node.parent = dataset_node

        if dataset.description.present?
          description_node = doc.create_element("v1:description")
          description_node.content = dataset.description
          description_node.parent = dataset_node
        end

        persons_node = doc.create_element("v1:persons")
        dataset.individual_creators.each do |creator|
          email = creator.email.to_s.strip
          next if email.blank?

          person_xml_doc = IllinoisExpertsClient.person_xml_doc(email)
          person_node = if person_xml_doc.present?
            internal_expert(doc: doc, creator: creator, person_xml_doc: person_xml_doc, dataset_release_date: dataset_release_date)
          elsif illinois_email?(email)
            illinois_external_expert(doc: doc, creator: creator, dataset_release_date: dataset_release_date)
          else
            external_expert(doc: doc, creator: creator, dataset_release_date: dataset_release_date)
          end
          person_node.parent = persons_node
        end
        persons_node.parent = dataset_node

        doi_node = doc.create_element("v1:DOI")
        doi_node.content = dataset.identifier
        doi_node.parent = dataset_node

        available_node = doc.create_element("v1:availableDate")
        year_node = doc.create_element("v3:year")
        year_node.content = dataset_release_date.strftime("%Y")
        year_node.parent = available_node

        month_node = doc.create_element("v3:month")
        month_node.content = dataset_release_date.strftime("%m")
        month_node.parent = available_node

        day_node = doc.create_element("v3:day")
        day_node.content = dataset_release_date.strftime("%d")
        day_node.parent = available_node

        available_node.parent = dataset_node

        publisher_node = doc.create_element("v1:publisher")
        publisher_node["lookupId"] = IdbConfig.fetch(:illinois_experts, :publisher_id, default: "").to_s
        publisher_node.parent = dataset_node

        if dataset.keywords.present?
          keywords_node = doc.create_element("v1:keywords")
          dataset.keywords.split(";").map(&:squish).reject(&:blank?).each do |keyword|
            keyword_node = doc.create_element("v1:keyword")
            keyword_node.content = keyword
            keyword_node.parent = keywords_node
          end
          keywords_node.parent = dataset_node if keywords_node.elements.any?
        end

        exported_count += 1
      end

      return nil if exported_count.zero?

      doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
    end

    def internal_expert(doc:, creator:, person_xml_doc:, dataset_release_date:)
      person_node = doc.create_element("v1:person")
      person_node["id"] = creator.email.to_s
      person_node["contactPerson"] = "true" if creator.contact_selected?

      role_node = doc.create_element("v1:role")
      role_node.content = "creator"
      role_node.parent = person_node

      nested_person_node = doc.create_element("v1:person")
      nested_person_node["lookupId"] = creator.email.to_s
      nested_person_node.parent = person_node

      organisations_node = doc.create_element("v1:organisations")
      org_uuids = person_xml_doc.xpath("//organisationalUnit/@uuid")
      if org_uuids.empty?
        organization_node = doc.create_element("v1:organisation")
        organization_node["lookupId"] = IdbConfig.fetch(:illinois_experts, :publisher_id, default: "").to_s
        organization_node.parent = organisations_node
      else
        org_uuids.each do |org_uuid|
          organization_node = doc.create_element("v1:organisation")
          organization_node["lookupId"] = org_uuid.content
          organization_node.parent = organisations_node
        end
      end
      organisations_node.parent = person_node

      date_node = doc.create_element("v1:associationStartDate")
      start_date_nodeset = person_xml_doc.xpath("//period/startDate")
      date_node.content = if start_date_nodeset.empty?
        dataset_release_date.strftime("%Y-%m-%d")
      else
        start_date_nodeset.first.content
      end
      date_node.parent = person_node

      person_node
    end

    def external_expert(doc:, creator:, dataset_release_date:)
      first_name, last_name = split_creator_name(creator)

      person_node = doc.create_element("v1:person")
      person_node["id"] = creator.email.to_s

      role_node = doc.create_element("v1:role")
      role_node.content = "creator"
      role_node.parent = person_node

      nested_person_node = doc.create_element("v1:person")
      nested_person_node["origin"] = "external"

      first_name_node = doc.create_element("v1:firstName")
      first_name_node.content = first_name
      first_name_node.parent = nested_person_node

      last_name_node = doc.create_element("v1:lastName")
      last_name_node.content = last_name
      last_name_node.parent = nested_person_node

      nested_person_node.parent = person_node

      organisations_node = doc.create_element("v1:organisations")
      organization_node = doc.create_element("v1:organisation")
      org_name_node = doc.create_element("v1:name")
      org_name_node.content = "unknown"
      org_name_node.parent = organization_node
      organization_node.parent = organisations_node
      organisations_node.parent = person_node

      date_node = doc.create_element("v1:associationStartDate")
      date_node.content = dataset_release_date.strftime("%Y-%m-%d")
      date_node.parent = person_node

      person_node
    end

    def illinois_external_expert(doc:, creator:, dataset_release_date:)
      first_name, last_name = split_creator_name(creator)

      person_node = doc.create_element("v1:person")
      person_node["id"] = creator.email.to_s

      role_node = doc.create_element("v1:role")
      role_node.content = "creator"
      role_node.parent = person_node

      nested_person_node = doc.create_element("v1:person")
      nested_person_node["origin"] = "external"

      first_name_node = doc.create_element("v1:firstName")
      first_name_node.content = first_name
      first_name_node.parent = nested_person_node

      last_name_node = doc.create_element("v1:lastName")
      last_name_node.content = last_name
      last_name_node.parent = nested_person_node

      nested_person_node.parent = person_node

      organisations_node = doc.create_element("v1:organisations")
      organization_node = doc.create_element("v1:organisation")
      organization_node["lookupId"] = IdbConfig.fetch(:illinois_experts, :illinois_external_org_id, default: "").to_s
      organization_node.parent = organisations_node
      organisations_node.parent = person_node

      date_node = doc.create_element("v1:associationStartDate")
      date_node.content = dataset_release_date.strftime("%Y-%m-%d")
      date_node.parent = person_node

      person_node
    end

    private

    def illinois_email?(email)
      email.to_s.strip.downcase.end_with?("@illinois.edu")
    end

    def split_creator_name(creator)
      given_name = creator.given_name.to_s.strip
      family_name = creator.family_name.to_s.strip
      return [ given_name, family_name ] if given_name.present? || family_name.present?

      parts = creator.display_name.to_s.strip.split
      return [ "", "" ] if parts.empty?
      return [ parts.first, "" ] if parts.length == 1

      [ parts.first, parts[1..].join(" ") ]
    end
  end
end
