module ArchiveExtractor
  class MockInvoker
    def invoke_extraction(datafile)
      raise ArgumentError, "datafile is required" if datafile.nil?

      request = datafile.archive_extract_request || datafile.build_archive_extract_request
      request.status = :sent
      request.sent_at = Time.current
      request.raw_response = { mock: true, invoked_at: Time.current.iso8601 }.to_json
      request.save!
      request
    end

    def current_task_count
      0
    end
  end
end
