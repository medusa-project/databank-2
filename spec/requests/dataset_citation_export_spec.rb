require "rails_helper"

RSpec.describe "Dataset citation export", type: :request do
  let(:dataset) do
    create(:dataset, :published, embargo: Dataset::EMBARGO_NONE, identifier: "10.5555/IDB-CITE",
                                 title: "Cite Me", publisher: "Illinois Data Bank")
  end

  {
    download_endnote_xml_dataset_path: [ "application/xml", "<ref-type name=\"Online Database\">45</ref-type>", "DOI-10.5555_IDB-CITE.xml" ],
    download_ris_dataset_path: [ "application/x-research-info-systems", "TY  - DATA", "DOI-10.5555_IDB-CITE.ris" ],
    download_bibtex_dataset_path: [ "application/x-bibtex", "title = {Cite Me}", "DOI-10.5555_IDB-CITE.bib" ],
    download_plaintext_citation_dataset_path: [ "text/plain", "Cite Me", "DOI-10.5555_IDB-CITE.txt" ]
  }.each do |path_helper, (type, content, filename)|
    it "serves #{path_helper}" do
      get public_send(path_helper, dataset)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(type)
      expect(response.body).to include(content)
      expect(response.headers["Content-Disposition"]).to include(filename)
    end
  end

  it "shows the Export Citation menu on the show page" do
    get dataset_path(dataset)

    expect(response.body).to include("Export Citation")
    expect(response.body).to include(download_ris_dataset_path(dataset))
  end
end
