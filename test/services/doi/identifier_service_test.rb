require "test_helper"

module Doi
  class IdentifierServiceTest < ActiveSupport::TestCase
    setup do
      @dataset = Dataset.create!(
        title: "DOI test dataset",
        description: "Dataset used for DOI service testing",
        owner_uid: "owner-doi",
        depositor_name: "DOI Owner",
        depositor_email: "doi-owner@example.edu"
      )
    end

    test "returns generated DOI when DataCite is not configured" do
      %w[DATACITE_API_BASE_URL DATACITE_USERNAME DATACITE_PASSWORD DATACITE_STRICT].each do |key|
        ENV.delete(key)
      end

      doi = IdentifierService.new(@dataset).mint_for_publish!

      assert_equal "10.5555/#{@dataset.key}", doi
    end

    test "returns existing identifier without reminting" do
      @dataset.update!(identifier: "10.5555/existing-doi")

      doi = IdentifierService.new(@dataset).mint_for_publish!

      assert_equal "10.5555/existing-doi", doi
    end
  end
end
