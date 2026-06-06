# frozen_string_literal: true

class IllinoisExpertsController < ApplicationController
  skip_before_action :authenticate_user!, only: :index

  # Responds to GET /illinois_experts.xml
  def index
    datasets_xml = Dataset.to_illinois_experts

    if datasets_xml.blank?
      render xml: { error: "error generating xml for datasets" }.to_xml
      return
    end

    render xml: datasets_xml
  end

  # Responds to GET /illinois_experts/persons.xml?email=...
  def persons
    authorize! :manage, IllinoisExpertsClient

    if params["email"].blank?
      render xml: { error: "missing email" }.to_xml
      return
    end

    person_xml = IllinoisExpertsClient.persons(params["email"])

    if person_xml.nil?
      render xml: { error: %(person not found in Illinois Experts, email: #{params["email"]}) }.to_xml
      return
    end

    render xml: person_xml
  end

  # Responds to GET /illinois_experts/example.xml
  def example
    authorize! :manage, IllinoisExpertsClient

    example_xml = IllinoisExpertsClient.example

    if example_xml.blank?
      render xml: { error: "example not found" }.to_xml
      return
    end

    render xml: example_xml
  end
end
