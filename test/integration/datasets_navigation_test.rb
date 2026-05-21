require "test_helper"

class DatasetsNavigationTest < ActionDispatch::IntegrationTest
  test "datasets page includes primary header navigation links" do
    get datasets_path

    assert_response :success
    assert_includes response.body, "<il-header-nav"
    assert_includes response.body, "Deposit Dataset"
    assert_includes response.body, "Find Data"
    assert_includes response.body, "Policies"
    assert_includes response.body, "Guides"
    assert_includes response.body, "Contact Us"
  end
end
