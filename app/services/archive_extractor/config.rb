module ArchiveExtractor
  module Config
    module_function

    def enabled?
      IdbConfig.fetch(:extractor, :enabled, default: "false").to_s.casecmp("true").zero?
    end

    def use_mocks?
      env_mock = Rails.env.development? || Rails.env.test?
      configured_mock = IdbConfig.fetch(:extractor, :use_mocks, default: "false").to_s.casecmp("true").zero?
      env_mock || configured_mock
    end

    def aws_region
      IdbConfig.fetch(:extractor, :aws_region, default: "us-east-2").to_s
    end

    def aws_sqs_queue_url
      IdbConfig.fetch(:extractor, :aws_sqs_queue_url, default: "").to_s
    end

    def ecs_cluster
      IdbConfig.fetch(:extractor, :ecs_cluster, default: "").to_s
    end

    def ecs_task_definition
      IdbConfig.fetch(:extractor, :ecs_task_definition, default: "").to_s
    end

    def ecs_container_name
      IdbConfig.fetch(:extractor, :ecs_container_name, default: "").to_s
    end

    def ecs_subnets
      Array(IdbConfig.fetch(:extractor, :ecs_subnets, default: [])).map(&:to_s).reject(&:blank?)
    end

    def ecs_security_groups
      Array(IdbConfig.fetch(:extractor, :ecs_security_groups, default: [])).map(&:to_s).reject(&:blank?)
    end

    def ecs_platform_version
      IdbConfig.fetch(:extractor, :ecs_platform_version, default: "1.4.0").to_s
    end

    def max_task_capacity
      IdbConfig.fetch(:extractor, :max_task_capacity, default: "49").to_i
    end

    def max_batch_size
      IdbConfig.fetch(:extractor, :max_batch_size, default: "9").to_i
    end
  end
end
