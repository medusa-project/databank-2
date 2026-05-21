require "rails_helper"

RSpec.describe Migration::SampleFetchService do
  let(:tmp_root) { Rails.root.join("tmp", "spec_sample_fetch") }
  let(:list_path) { tmp_root.join("datasets.json") }

  before do
    FileUtils.rm_rf(tmp_root)
    FileUtils.mkdir_p(tmp_root)
    File.write(
      list_path,
      JSON.pretty_generate([
        {
          "identifier" => "10.13012/B2IDB-1234567_V1",
          "url" => "https://databank.illinois.edu/datasets/IDB-1234567.json"
        }
      ])
    )
  end

  after do
    FileUtils.rm_rf(tmp_root)
  end

  it "fetches payload and writes run summary" do
    response = instance_double("Net::HTTPSuccess", is_a?: true, body: { title: "Fetched", identifier: "10.13012/B2IDB-1234567_V1" }.to_json)

    allow(Net::HTTP).to receive(:start).and_yield(instance_double("Net::HTTP", request: response))

    summary = described_class.new(list_path: list_path.to_s, output_root: tmp_root.to_s).call

    expect(summary[:fetched]).to eq(1)
    expect(summary[:failed]).to eq(0)

    run_dir = Pathname(summary[:run_dir])
    expect(run_dir.join("summary.json")).to exist
    expect(Dir.glob(run_dir.join("datasets", "*.json").to_s).length).to eq(1)
  end
end
