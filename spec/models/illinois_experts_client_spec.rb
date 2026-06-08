require "rails_helper"

RSpec.describe IllinoisExpertsClient, type: :model do
  describe ".person_xml_doc" do
    before do
      allow(IdbConfig).to receive(:fetch).and_call_original
    end

    it "requires a non-blank email address" do
      expect do
        described_class.person_xml_doc(" ")
      end.to raise_error(ArgumentError, "must provide email address string")
    end

    it "returns nil when the Illinois Experts config is incomplete" do
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("secret")

      expect(described_class.person_xml_doc("person@example.edu")).to be_nil
    end

    it "fetches and parses a person record while stripping namespaces" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("<ns:person xmlns:ns='urn:test'><ns:name>Test Person</ns:name></ns:person>")

      http = instance_double(Net::HTTP)
      sock = instance_double(Net::HTTP)
      captured_request = nil

      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("https://experts.example.edu/api")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("secret")
      allow(Net::HTTP).to receive(:new).with("experts.example.edu", 443).and_return(sock)
      allow(sock).to receive(:use_ssl=).with(true)
      allow(sock).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      doc = described_class.person_xml_doc(" person+test@example.edu ")

      expect(captured_request.path).to eq("/api/persons/person%2Btest%40example.edu?apiKey=secret")
      expect(doc.at_xpath("//person/name").text).to eq("Test Person")
    end

    it "returns nil when the Experts request fails" do
      sock = instance_double(Net::HTTP)

      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("https://experts.example.edu/api")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("secret")
      allow(Net::HTTP).to receive(:new).with("experts.example.edu", 443).and_return(sock)
      allow(sock).to receive(:use_ssl=).with(true)
      allow(sock).to receive(:start).and_raise(SocketError)

      expect(described_class.person_xml_doc("person@example.edu")).to be_nil
    end

    it "returns nil when XML parsing raises a syntax error" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("<person>")

      http = instance_double(Net::HTTP, request: response)
      sock = instance_double(Net::HTTP)

      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("https://experts.example.edu/api")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("secret")
      allow(Net::HTTP).to receive(:new).with("experts.example.edu", 443).and_return(sock)
      allow(sock).to receive(:use_ssl=).with(true)
      allow(sock).to receive(:start).and_yield(http)
      allow(Nokogiri).to receive(:XML).and_raise(Nokogiri::XML::SyntaxError.new("bad xml"))

      expect(described_class.person_xml_doc("person@example.edu")).to be_nil
    end
  end

  describe ".persons" do
    it "returns nil when no person document is found" do
      allow(described_class).to receive(:person_xml_doc).with("person@example.edu").and_return(nil)

      expect(described_class.persons("person@example.edu")).to be_nil
    end

    it "serializes the person XML document" do
      doc = Nokogiri::XML("<person><name>Test Person</name></person>")
      allow(described_class).to receive(:person_xml_doc).with("person@example.edu").and_return(doc)

      expect(described_class.persons("person@example.edu")).to include("<person>")
      expect(described_class.persons("person@example.edu")).to include("Test Person")
    end
  end

  describe ".example" do
    before do
      allow(IdbConfig).to receive(:fetch).and_call_original
    end

    it "returns nil when the Illinois Experts config is incomplete" do
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("https://experts.example.edu/api")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("")

      expect(described_class.example).to be_nil
    end

    it "returns the datasets example response body and sends the API key header" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("<datasets><dataset /></datasets>")

      http = instance_double(Net::HTTP)
      sock = instance_double(Net::HTTP)
      captured_request = nil

      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("https://experts.example.edu/api")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("secret")
      allow(Net::HTTP).to receive(:new).with("experts.example.edu", 443).and_return(sock)
      allow(sock).to receive(:use_ssl=).with(true)
      allow(sock).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      body = described_class.example

      expect(captured_request.path).to eq("/api/datasets")
      expect(captured_request["api-key"]).to eq("secret")
      expect(body).to eq("<datasets><dataset /></datasets>")
    end

    it "returns nil when the datasets example request fails" do
      sock = instance_double(Net::HTTP)

      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :endpoint, default: "").and_return("https://experts.example.edu/api")
      allow(IdbConfig).to receive(:fetch).with(:illinois_experts, :key, default: "").and_return("secret")
      allow(Net::HTTP).to receive(:new).with("experts.example.edu", 443).and_return(sock)
      allow(sock).to receive(:use_ssl=).with(true)
      allow(sock).to receive(:start).and_raise(IOError)

      expect(described_class.example).to be_nil
    end
  end
end
