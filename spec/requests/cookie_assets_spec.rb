require "rails_helper"

RSpec.describe "Relative cookie banner assets", type: :request do
  [ "/datasets", "/datasets/IDB-2358320" ].each do |prefix|
    %w[
      css/ila-cookie-uiuc-colors.css
      css/ila-slideover.css
      css/ila-cookie-banner.css
      partials/ila-cookie-banner-content.part.html
    ].each do |asset|
      it "redirects #{prefix}/#{asset} to the canonical public asset" do
        get "#{prefix}/#{asset}"

        expect(response).to redirect_to("/#{asset}")
      end
    end
  end
end
