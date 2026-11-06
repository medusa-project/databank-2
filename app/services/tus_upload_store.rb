require "securerandom"
require "tus/storage/s3"

class TusUploadStore
  class UploadNotFound < StandardError; end
  class OffsetMismatch < StandardError; end
  class InvalidUploadId < StandardError; end
  class InvalidUpload < StandardError; end

  MAX_UPLOAD_SIZE = 50 * 1024**3
  MAX_CHUNK_SIZE = 64 * 1024**2
  UPLOAD_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

  def self.create(upload_length:, metadata:, dataset_key:)
    length = Integer(upload_length, 10)
    raise InvalidUpload unless length.between?(0, MAX_UPLOAD_SIZE)

    store = new(SecureRandom.uuid)
    info = {
      "Upload-Length" => length.to_s,
      "Upload-Offset" => "0",
      "metadata" => metadata,
      "dataset_key" => dataset_key
    }

    if length.zero?
      store.storage.bucket.object(store.object_key).put(body: "")
    else
      store.storage.create_file(store.upload_id, info)
    end
    begin
      store.storage.update_info(store.upload_id, info)
    rescue StandardError
      store.storage.delete_file(store.upload_id, info)
      raise
    end
    store.upload_id
  end

  attr_reader :upload_id

  def initialize(upload_id)
    @upload_id = upload_id.to_s.downcase
    raise InvalidUploadId unless @upload_id.match?(UPLOAD_ID_PATTERN)
  end

  def storage
    @storage ||= begin
      root = StorageManager.instance.draft_root
      raise "Tus requires an S3 draft root" unless root.root_type == :s3

      Tus::Storage::S3.new(bucket: root.bucket, prefix: "#{root.prefix}tus", **root.client_args)
    end
  end

  def object_key
    "#{storage.prefix}/#{upload_id}"
  end

  def storage_key
    "tus/#{upload_id}"
  end

  def with_lock
    ActiveRecord::Base.transaction do
      connection = ActiveRecord::Base.connection
      connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote("tus:#{upload_id}")}, 0))")
      yield
    end
  end

  def state(dataset_key:)
    info = storage.read_info(upload_id)
    raise UploadNotFound unless info["dataset_key"] == dataset_key

    if info["multipart_id"]
      object = storage.bucket.object(object_key)
      if object.exists? && object.content_length == Integer(info.fetch("Upload-Length"), 10)
        info["Upload-Offset"] = info.fetch("Upload-Length")
        info.delete("multipart_id")
        info.delete("multipart_parts")
        storage.update_info(upload_id, info)
      end
    end
    info
  rescue Tus::NotFound
    raise UploadNotFound
  end

  def append_chunk!(dataset_key:, expected_offset:, chunk_io:, content_length:)
    info = state(dataset_key: dataset_key)
    offset = Integer(expected_offset, 10)
    length = Integer(content_length)
    total = Integer(info.fetch("Upload-Length"), 10)
    raise OffsetMismatch unless offset == Integer(info.fetch("Upload-Offset"), 10)
    raise InvalidUpload unless length.positive? && length <= MAX_CHUNK_SIZE && offset + length <= total

    min_part = [ Tus::Storage::S3::MIN_PART_SIZE, (total + 9_999) / 10_000 ].max
    raise InvalidUpload if length < min_part && offset + length < total

    uploaded = storage.patch_file(upload_id, chunk_io, info)
    raise InvalidUpload, "S3 did not accept the upload chunk" if uploaded.zero?

    info["Upload-Offset"] = (offset + uploaded).to_s
    storage.finalize_file(upload_id, info) if offset + uploaded == total
    storage.update_info(upload_id, info)
    offset + uploaded
  end

  def remove_info!
    storage.bucket.object("#{object_key}.info").delete
  end
end
