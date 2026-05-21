require "test_helper"

class SessionsShibbolethTest < ActionDispatch::IntegrationTest
  test "shibboleth callback signs in from proxy headers" do
    post "/auth/shibboleth/callback", headers: {
      "REMOTE_USER" => "netid@example.edu",
      "HTTP_MAIL" => "netid@example.edu",
      "HTTP_DISPLAYNAME" => "Net Id"
    }

    assert_response :redirect
    assert_redirected_to root_path

    user = User.find_by(provider: "shibboleth", uid: "netid@example.edu")
    assert_not_nil user
    assert_equal "netid@example.edu", user.email
    assert_equal "Net Id", user.name
  end

  test "shibboleth callback fails when required headers are missing" do
    post "/auth/shibboleth/callback"

    assert_response :redirect
    assert_redirected_to login_path
    follow_redirect!
    assert_includes response.body, "Authentication failed."
  end
end
