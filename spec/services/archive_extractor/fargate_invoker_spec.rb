require "rails_helper"

RSpec.describe ArchiveExtractor::FargateInvoker, type: :service do
  let(:ecs_client) { double("ecs_client") }
  let(:logger) { instance_double(Logger, error: nil, warn: nil) }
  let(:invoker) { described_class.new(ecs_client: ecs_client, logger: logger) }

  describe "#invoke_extraction" do
    let(:datafile) { create(:datafile) }
    let(:storage_root) { double("storage_root", bucket: "draft-bucket") }

    before do
      allow(datafile).to receive(:current_root).and_return(storage_root)
      allow(datafile).to receive(:storage_key_with_prefix).and_return("uploads/archive.zip")
      allow(datafile).to receive(:binary_name).and_return("archive.zip")
      allow(datafile.binary).to receive(:content_type).and_return("application/zip")
    end

    it "submits an ECS task and marks request sent" do
      allow(ecs_client).to receive(:run_task).and_return(double(failures: []))

      request = invoker.invoke_extraction(datafile)

      expect(request).to be_persisted
      expect(request.status).to eq("sent")
      expect(request.sent_at).to be_present
      expect(ecs_client).to have_received(:run_task) do |payload|
        command = payload.dig(:overrides, :container_overrides, 0, :command).last
        expect(command).to include("Extractor.extract 'draft-bucket', 'uploads/archive.zip', 'archive.zip', '#{datafile.web_id}', 'application/zip'")
      end
    end

    it "marks request failed when ECS returns failures" do
      allow(ecs_client).to receive(:run_task).and_return(double(failures: [ { arn: "task-1" } ]))

      expect { invoker.invoke_extraction(datafile) }
        .to raise_error(StandardError, /run_task failed/)

      expect(datafile.archive_extract_request.reload.status).to eq("failed")
      expect(datafile.archive_extract_request.raw_response).to include("task-1")
    end
  end

  describe "#current_task_count" do
    it "returns number of active ECS tasks" do
      allow(ecs_client).to receive(:list_tasks).and_return(double(task_arns: %w[a b c]))

      expect(invoker.current_task_count).to eq(3)
    end

    it "returns zero when ECS list tasks fails" do
      allow(ecs_client).to receive(:list_tasks).and_raise(StandardError, "boom")

      expect(invoker.current_task_count).to eq(0)
    end
  end
end
