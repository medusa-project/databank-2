require "rails_helper"

RSpec.describe Datafile::Viewable do
  describe ".peek_type_from_mime" do
    it "returns all_text for text files under the display threshold" do
      expect(Datafile.peek_type_from_mime("text/plain", Datafile::Viewable::ALLOWED_DISPLAY_BYTES)).to eq(Datafile::PeekType::ALL_TEXT)
    end

    it "returns part_text for text files above the display threshold" do
      expect(Datafile.peek_type_from_mime("text/plain", Datafile::Viewable::ALLOWED_DISPLAY_BYTES + 1)).to eq(Datafile::PeekType::PART_TEXT)
    end

    it "returns listing for recognized archive MIME subtypes" do
      expect(Datafile.peek_type_from_mime("application/zip", 1024)).to eq(Datafile::PeekType::LISTING)
    end

    it "returns none for unknown MIME types" do
      expect(Datafile.peek_type_from_mime("application/octet-stream", 1024)).to eq(Datafile::PeekType::NONE)
    end

    it "returns markdown for markdown MIME types" do
      expect(Datafile.peek_type_from_mime("text/markdown", 1024)).to eq(Datafile::PeekType::MARKDOWN)
    end
  end

  describe "text predicates" do
    let(:dataset) { create(:dataset) }

    it "treats all_text and part_text as text previews" do
      all_text = build(:datafile, dataset: dataset, attach_binary: false, peek_type: Datafile::PeekType::ALL_TEXT)
      part_text = build(:datafile, dataset: dataset, attach_binary: false, peek_type: Datafile::PeekType::PART_TEXT)
      archive = build(:datafile, dataset: dataset, attach_binary: false, peek_type: Datafile::PeekType::LISTING)

      expect(all_text.text?).to be(true)
      expect(part_text.text?).to be(true)
      expect(archive.text?).to be(false)
    end
  end

  describe "peek persistence on save" do
    let(:dataset) { create(:dataset) }

    it "stores all_text peek content for small text uploads" do
      datafile = create(:datafile, dataset: dataset)

      expect(datafile.reload.peek_type).to eq(Datafile::PeekType::ALL_TEXT)
      expect(datafile.peek_content).to include("column_a,column_b")
    end

    it "stores part_text peek content for large text uploads" do
      large_text = ("a" * (Datafile::Viewable::ALLOWED_DISPLAY_BYTES + 128))
      datafile = build(:datafile, dataset: dataset, attach_binary: false, binary_name: "large.txt")
      datafile.binary.attach(
        io: StringIO.new(large_text),
        filename: "large.txt",
        content_type: "text/plain"
      )
      datafile.sync_metadata_from_attachment!
      datafile.save!

      datafile.reload
      expect(datafile.peek_type).to eq(Datafile::PeekType::PART_TEXT)
      expect(datafile.peek_content.length).to eq(Datafile::Viewable::ALLOWED_DISPLAY_BYTES)
    end

    it "does not overwrite existing peek_content" do
      datafile = create(:datafile, dataset: dataset, peek_type: Datafile::PeekType::ALL_TEXT, peek_content: "precomputed")

      expect(datafile.reload.peek_content).to eq("precomputed")
    end

    it "stores markdown peek type and content based on filename extension" do
      markdown_source = "# Title\n\nBody text"
      datafile = build(:datafile, dataset: dataset, attach_binary: false, binary_name: "README.md")
      datafile.binary.attach(
        io: StringIO.new(markdown_source),
        filename: "README.md",
        content_type: "text/plain"
      )
      datafile.sync_metadata_from_attachment!
      datafile.save!

      datafile.reload
      expect(datafile.peek_type).to eq(Datafile::PeekType::MARKDOWN)
      expect(datafile.peek_content).to include("# Title")
      expect(datafile.peek_content).to include("Body text")
    end
  end
end
