require "rails_helper"
require "rake"

RSpec.describe "configuration contract tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("config:contract")
  end

  let(:app_config) do
    {
      app: { url: "https://databank.example.test", root_url_text: "https://databank.example.test" },
      mail: { from: "noreply@example.test" },
      doi: { strict: false },
      ingest: { events_enabled: false },
      globus: { transfer_enabled: false }
    }.with_indifferent_access
  end
  let(:storage_config) do
    {
      storage: %w[draft medusa globus_download globus_ingest message reports].map do |name|
        { name: name, type: "s3", region: "us-east-2", bucket: "example-#{name}" }
      end + [ { name: "tmpfs", type: "filesystem", path: "/tmp" } ]
    }
  end
  let(:credentials) { {} }

  before do
    stub_const("IDB_CONFIG", app_config)
    stub_const("STORAGE_CONFIG", storage_config)
    allow(Rails.application).to receive(:credentials).and_return(credentials)
    allow(Rails.application.config.active_storage).to receive(:service).and_return(:test)
    Rake::Task["config:contract"].reenable
    Rake::Task["config:contract_report"].reenable
  end

  def expect_contract_failure(*messages)
    expect do
      expect { Rake::Task["config:contract"].invoke }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end.to output(
      "Configuration contract check failed for RAILS_ENV=test.\n" \
      "#{messages.map { |message| "- #{message}" }.join("\n")}\n"
    ).to_stderr
  end

  describe "config:contract" do
    it "passes with valid core/storage settings and disabled integrations" do
      expect { Rake::Task["config:contract"].invoke }.to output(
        "Configuration contract check passed for RAILS_ENV=test.\n"
      ).to_stdout
    end

    it "reports all missing core values together instead of failing on only the first" do
      app_config[:app][:url] = nil
      app_config[:app][:root_url_text] = " "
      app_config[:mail][:from] = ""

      expect_contract_failure(
        "IDB_CONFIG.app.url is missing",
        "IDB_CONFIG.app.root_url_text is missing",
        "IDB_CONFIG.mail.from is missing"
      )
    end

    %w[draft medusa globus_download globus_ingest message reports tmpfs].each do |name|
      it "rejects a missing #{name} storage root" do
        storage_config[:storage].reject! { |root| root[:name] == name }

        expect_contract_failure("STORAGE_CONFIG.storage is missing roots: #{name}")
      end
    end

    it "reports every required root when the storage list is absent" do
      storage_config.delete(:storage)

      expect_contract_failure(
        "STORAGE_CONFIG.storage is missing roots: draft, medusa, globus_download, globus_ingest, message, reports, tmpfs"
      )
    end

    %i[region bucket].each do |field|
      it "rejects a blank S3 #{field} with the root name" do
        storage_config[:storage].first[field] = " "

        expect_contract_failure("STORAGE_CONFIG.storage[draft].#{field} is missing")
      end
    end

    it "rejects a missing filesystem path" do
      storage_config[:storage].last.delete(:path)

      expect_contract_failure("STORAGE_CONFIG.storage[tmpfs].path is missing")
    end

    it "rejects unsupported storage types" do
      storage_config[:storage].first[:type] = "unknown"

      expect_contract_failure("STORAGE_CONFIG.storage[draft].type must be 's3' or 'filesystem' (found 'unknown')")
    end

    {
      doi: { flag: :strict, fields: %i[api_base_url username password] },
      ingest: { flag: :events_enabled, fields: %i[rabbitmq_url requests_queue] },
      globus: { flag: :transfer_enabled, fields: %i[transfer_endpoint transfer_token source_collection destination_collection] }
    }.each do |integration, definition|
      [ true, "true", "1" ].each do |enabled|
        it "requires all #{integration} settings when #{definition[:flag]} is #{enabled.inspect}" do
          app_config[integration][definition[:flag]] = enabled

          expect_contract_failure(*definition[:fields].map { |field| "IDB_CONFIG.#{integration}.#{field} is missing" })
        end
      end

      [ false, "false", "0" ].each do |disabled|
        it "does not require #{integration} settings when #{definition[:flag]} is #{disabled.inspect}" do
          app_config[integration][definition[:flag]] = disabled

          expect { Rake::Task["config:contract"].invoke }.to output(
            "Configuration contract check passed for RAILS_ENV=test.\n"
          ).to_stdout
        end
      end

      it "passes when enabled #{integration} has every required value" do
        app_config[integration][definition[:flag]] = true
        definition[:fields].each { |field| app_config[integration][field] = "configured-#{field}" }

        expect { Rake::Task["config:contract"].invoke }.to output(
          "Configuration contract check passed for RAILS_ENV=test.\n"
        ).to_stdout
      end
    end

    it "rejects the old topic configuration when the Medusa request queue is missing" do
      app_config[:ingest].merge!(
        events_enabled: true, rabbitmq_url: "amqp://example.test",
        events_exchange: "databank.ingest", events_routing_key: "dataset.published"
      )

      expect_contract_failure("IDB_CONFIG.ingest.requests_queue is missing")
    end

    describe "Amazon Active Storage" do
      let(:amazon_config) do
        {
          "region" => "us-east-2", "bucket" => "active-storage-example",
          "access_key_id" => "test-access-key", "secret_access_key" => "test-secret-key"
        }
      end

      before do
        allow(Rails.application.config.active_storage).to receive(:service).and_return(:amazon)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(Rails.root.join("config", "storage.yml")) do
          { "amazon" => amazon_config }.to_yaml
        end
      end

      it "passes without warnings when region, bucket, and explicit credentials exist" do
        expect { Rake::Task["config:contract"].invoke }.to output(
          "Configuration contract check passed for RAILS_ENV=test.\n"
        ).to_stdout
      end

      %w[region bucket].each do |field|
        it "rejects a missing Amazon #{field}" do
          amazon_config.delete(field)

          expect_contract_failure("config/storage.yml amazon.#{field} is missing")
        end
      end

      %w[access_key_id secret_access_key].each do |field|
        it "warns but permits IAM role authentication when #{field} is blank" do
          amazon_config[field] = ""

          expect { Rake::Task["config:contract"].invoke }.to output(
            "Configuration contract check passed for RAILS_ENV=test.\n" \
            "WARN: Active Storage amazon credentials are blank; this is valid only with instance/profile-based IAM auth\n"
          ).to_stdout
        end
      end

      it "reports required fields when storage YAML is empty" do
        allow(File).to receive(:read).with(Rails.root.join("config", "storage.yml")).and_return("")

        expect_contract_failure(
          "config/storage.yml amazon.region is missing",
          "config/storage.yml amazon.bucket is missing"
        )
      end
    end
  end

  describe "config:contract_report" do
    before do
      allow(ENV).to receive(:key?).and_call_original
      %w[
        APP_URL ROOT_URL_TEXT IDB_MAIL_FROM STORAGE_S3_REGION
        STORAGE_DRAFT_BUCKET STORAGE_MEDUSA_BUCKET STORAGE_GLOBUS_BUCKET
        STORAGE_DRAFT_PREFIX STORAGE_MEDUSA_PREFIX STORAGE_GLOBUS_DOWNLOAD_PREFIX AWS_S3_BUCKET
      ].each { |key| allow(ENV).to receive(:key?).with(key).and_return(false) }
    end

    it "reports defaults and missing settings without exposing resolved values" do
      expect { Rake::Task["config:contract_report"].invoke }.to output(
        "Config source report for RAILS_ENV=test\n" \
        "- idb.app.url | source=default | status=set\n" \
        "- idb.app.root_url_text | source=default | status=set\n" \
        "- idb.mail.from | source=default | status=set\n" \
        "- storage.region | source=default | status=set\n" \
        "- storage.draft_bucket | source=missing | status=missing\n" \
        "- storage.medusa_bucket | source=missing | status=missing\n" \
        "- storage.globus_bucket | source=missing | status=missing\n" \
        "- storage.draft_prefix | source=default | status=set\n" \
        "- storage.medusa_prefix | source=default | status=set\n" \
        "- storage.globus_download_prefix | source=default | status=set\n" \
        "- active_storage.bucket | source=missing | status=missing\n"
      ).to_stdout
    end

    it "reports environment sources without reading their values" do
      allow(ENV).to receive(:key?).with("APP_URL").and_return(true)
      allow(ENV).to receive(:key?).with("STORAGE_MEDUSA_BUCKET").and_return(true)
      allow(ENV).to receive(:key?).with("AWS_S3_BUCKET").and_return(true)
      expect(ENV).not_to receive(:[]).with("AWS_S3_BUCKET")

      expect { Rake::Task["config:contract_report"].invoke }.to output(
        a_string_including(
          "- idb.app.url | source=env:APP_URL | status=set\n",
          "- storage.medusa_bucket | source=env:STORAGE_MEDUSA_BUCKET | status=set\n",
          "- active_storage.bucket | source=env:AWS_S3_BUCKET | status=set\n"
        )
      ).to_stdout
    end

    it "prefers credentials over environment sources and never prints credentials or config values" do
      credentials.merge!(
        app_url: "private-app-value", root_url_text: "private-root-value",
        system_user_email: "private-mail-value",
        aws: { region: "private-region-value", secret_access_key: "private-secret-value" },
        storage: {
          draft_bucket: "private-draft-value", medusa_bucket: "private-medusa-value",
          globus_bucket: "private-globus-value", active_storage_bucket: "private-active-value",
          draft_prefix: "private-prefix-value"
        },
        datacite: { password: "private-doi-password" },
        ingest: { rabbitmq_url: "private-broker-value" }
      )
      allow(ENV).to receive(:key?).with("APP_URL").and_return(true)
      allow(ENV).to receive(:key?).with("AWS_S3_BUCKET").and_return(true)
      output = StringIO.new
      original_stdout = $stdout
      begin
        $stdout = output
        Rake::Task["config:contract_report"].invoke
      ensure
        $stdout = original_stdout
      end

      expect(output.string).to include(
        "- idb.app.url | source=credentials | status=set\n",
        "- idb.app.root_url_text | source=credentials | status=set\n",
        "- idb.mail.from | source=credentials | status=set\n",
        "- storage.region | source=credentials | status=set\n",
        "- storage.draft_bucket | source=credentials | status=set\n",
        "- storage.draft_prefix | source=credentials | status=set\n",
        "- active_storage.bucket | source=credentials | status=set\n"
      )
      expect(output.string).not_to include("private-", app_config[:app][:url], app_config[:mail][:from])
    end

    it "reports the draft bucket credential fallback for Active Storage" do
      credentials[:storage] = { draft_bucket: "private-draft-value" }
      allow(ENV).to receive(:key?).with("AWS_S3_BUCKET").and_return(true)

      expect { Rake::Task["config:contract_report"].invoke }.to output(
        a_string_including("- active_storage.bucket | source=credentials:fallback(draft_bucket) | status=set\n")
      ).to_stdout
    end

    it "reports missing resolved core values even when defaults are their source" do
      app_config[:app][:url] = ""
      app_config[:app][:root_url_text] = nil
      app_config[:mail][:from] = " "
      storage_config[:storage].first.delete(:region)

      expect { Rake::Task["config:contract_report"].invoke }.to output(
        a_string_including(
          "- idb.app.url | source=default | status=missing\n",
          "- idb.app.root_url_text | source=default | status=missing\n",
          "- idb.mail.from | source=default | status=missing\n",
          "- storage.region | source=default | status=missing\n"
        )
      ).to_stdout
    end
  end
end
