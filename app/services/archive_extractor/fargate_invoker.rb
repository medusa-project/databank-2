require "json"

begin
  require "aws-sdk-ecs"
rescue LoadError
  # ECS client dependency is optional until extractor integration is enabled.
end

module ArchiveExtractor
  class FargateInvoker
    def initialize(ecs_client: default_ecs_client, logger: Rails.logger)
      @ecs_client = ecs_client
      @logger = logger
    end

    def invoke_extraction(datafile)
      raise ArgumentError, "datafile is required" if datafile.nil?

      request = datafile.archive_extract_request || datafile.build_archive_extract_request
      request.status = :sent
      request.sent_at = Time.current
      request.save!

      response = @ecs_client.run_task(build_task(command_string_for(datafile)))
      failures = response.respond_to?(:failures) ? Array(response.failures) : Array(response[:failures])

      if failures.any?
        request.update!(status: :failed, raw_response: failures.to_json)
        raise StandardError, "Extractor ECS run_task failed for datafile #{datafile.web_id}"
      end

      request
    rescue StandardError => e
      @logger.error("ArchiveExtractor::FargateInvoker invoke_extraction failed: #{e.class}: #{e.message}")
      raise
    end

    def current_task_count
      tasks = @ecs_client.list_tasks(cluster: Config.ecs_cluster)
      task_arns = tasks.respond_to?(:task_arns) ? tasks.task_arns : tasks[:task_arns]
      Array(task_arns).count
    rescue StandardError => e
      @logger.warn("ArchiveExtractor::FargateInvoker current_task_count unavailable: #{e.class}: #{e.message}")
      0
    end

    private

    def default_ecs_client
      raise LoadError, "aws-sdk-ecs is not available" unless defined?(Aws::ECS::Client)

      Aws::ECS::Client.new(region: Config.aws_region)
    end

    def command_string_for(datafile)
      bucket = storage_bucket_for(datafile)
      storage_key = datafile.storage_key_with_prefix

      raise ArgumentError, "storage_key is missing for datafile #{datafile.web_id}" if storage_key.blank?

      [
        "Extractor.extract '",
        bucket,
        "', '",
        storage_key,
        "', '",
        datafile.binary_name.to_s,
        "', '",
        datafile.web_id.to_s,
        "', '",
        datafile.binary&.content_type.to_s,
        "'"
      ].join
    end

    def storage_bucket_for(datafile)
      root = datafile.current_root
      raise ArgumentError, "storage root is missing for datafile #{datafile.web_id}" if root.nil?

      if root.respond_to?(:bucket)
        root.bucket.to_s
      elsif root.respond_to?(:bucket_name)
        root.bucket_name.to_s
      elsif root.respond_to?(:options)
        root.options[:bucket].to_s
      else
        raise ArgumentError, "Unable to resolve storage bucket for datafile #{datafile.web_id}"
      end
    end

    def build_task(command)
      {
        cluster: Config.ecs_cluster,
        count: 1,
        launch_type: "FARGATE",
        network_configuration: {
          awsvpc_configuration: {
            subnets: Config.ecs_subnets,
            security_groups: Config.ecs_security_groups,
            assign_public_ip: "ENABLED"
          }
        },
        overrides: {
          container_overrides: [
            {
              name: Config.ecs_container_name,
              command: [ "ruby", "-r", "./lib/extractor.rb", "-e", command ]
            }
          ]
        },
        platform_version: Config.ecs_platform_version,
        task_definition: Config.ecs_task_definition
      }
    end
  end
end
