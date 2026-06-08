require "rails_helper"

RSpec.describe ArchiveExtractor::ResponseConsumer, type: :service do
  let(:sqs_client) { double("sqs_client") }
  let(:message_root) { double("message_root") }
  let(:logger) { instance_double(Logger, error: nil, warn: nil) }
  let(:queue_url) { "https://example.test/queue/archive-extractor" }
  let(:consumer) do
    described_class.new(
      sqs_client: sqs_client,
      queue_url: queue_url,
      message_root: message_root,
      logger: logger
    )
  end

  describe "#poll_responses" do
    let(:datafile) { create(:datafile, peek_type: nil, peek_content: nil) }
    let!(:request) { ArchiveExtractRequest.create!(datafile: datafile, status: :pending) }

    it "persists successful extractor responses and updates datafile peek" do
      envelope = {
        "object_key" => "messages/#{datafile.web_id}.json",
        "s3_status" => "success",
        "error" => []
      }
      payload = {
        "web_id" => datafile.web_id,
        "status" => "success",
        "peek_type" => "listing",
        "peek_text" => "peek result",
        "error" => [
          { "error_type" => "example", "report" => "example report" }
        ]
      }

      message = double("message", body: envelope.to_json, receipt_handle: "receipt-1")
      allow(sqs_client).to receive(:receive_message).and_return(double(messages: [ message ]))
      allow(sqs_client).to receive(:delete_message)

      allow(message_root).to receive(:exist?).with("#{datafile.web_id}.json").and_return(true)
      allow(message_root).to receive(:as_string).with("#{datafile.web_id}.json").and_return(payload.to_json)
      allow(message_root).to receive(:delete_content).with("#{datafile.web_id}.json")

      summary = consumer.poll_responses(batch_size: 5)

      expect(summary.processed).to eq(1)
      expect(summary.succeeded).to eq(1)
      expect(summary.failed).to eq(0)
      expect(summary.skipped).to eq(0)
      expect(sqs_client).to have_received(:delete_message).with(queue_url: queue_url, receipt_handle: "receipt-1")

      request.reload
      expect(request.status).to eq("success")
      expect(request.archive_extract_response).to be_present
      expect(request.archive_extract_response.status).to eq("success")
      expect(request.archive_extract_errors.count).to eq(1)
      expect(datafile.reload.peek_type).to eq("listing")
      expect(datafile.peek_content).to eq("peek result")
    end

    it "skips messages without object_key and acknowledges the message" do
      envelope = { "s3_status" => "error", "error" => [] }
      message = double("message", body: envelope.to_json, receipt_handle: "receipt-2")
      allow(sqs_client).to receive(:receive_message).and_return(double(messages: [ message ]))
      allow(sqs_client).to receive(:delete_message)

      summary = consumer.poll_responses(batch_size: 1)

      expect(summary.processed).to eq(1)
      expect(summary.skipped).to eq(1)
      expect(summary.failed).to eq(0)
      expect(sqs_client).to have_received(:delete_message).with(queue_url: queue_url, receipt_handle: "receipt-2")
    end
  end
end
