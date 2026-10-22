require "rails_helper"

RSpec.describe DatasetsHelper, type: :helper do
  describe "#formatted_keywords" do
    it "adds a space after each semicolon" do
      expect(helper.formatted_keywords("a;b;c")).to eq("a; b; c")
    end

    it "does not double existing spacing" do
      expect(helper.formatted_keywords("a; b ;  c")).to eq("a; b; c")
    end

    it "drops blank entries" do
      expect(helper.formatted_keywords("a;;b;")).to eq("a; b")
    end

    it "keeps multi-word phrases intact" do
      expect(helper.formatted_keywords("file formats;institutional repositories"))
        .to eq("file formats; institutional repositories")
    end

    it "returns an empty string for nil" do
      expect(helper.formatted_keywords(nil)).to eq("")
    end
  end
end
