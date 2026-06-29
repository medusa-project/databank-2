module ArchiveExtractorPayloadHelper
  def archive_envelope(web_id:, s3_status: "success", error: [])
    {
      "object_key" => "messages/#{web_id}.json",
      "s3_status" => s3_status,
      "error" => error
    }
  end

  def archive_payload(
    web_id:,
    status: "success",
    peek_type: "listing",
    peek_text: "peek result",
    nested_items: nil,
    error: []
  )
    payload = {
      "web_id" => web_id,
      "status" => status,
      "peek_type" => peek_type,
      "peek_text" => peek_text,
      "error" => error
    }

    payload["nested_items"] = nested_items unless nested_items.nil?
    payload
  end
end
