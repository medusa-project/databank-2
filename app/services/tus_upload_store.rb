require "fileutils"
require "json"
require "securerandom"

class TusUploadStore
  class UploadNotFound < StandardError; end
  class OffsetMismatch < StandardError; end
  class InvalidUploadId < StandardError; end

  UPLOAD_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

  def self.create(upload_length:, metadata: {})
    upload_id = SecureRandom.uuid
    store = new(upload_id)
    store.write_state(
      "id" => upload_id,
      "length" => Integer(upload_length),
      "offset" => 0,
      "metadata" => metadata
    )
    upload_id
  end

  def initialize(upload_id)
    @upload_id = normalize_upload_id(upload_id)
  end

  def upload_id
    @upload_id
  end

  def exists?
    File.exist?(state_path)
  end

  def state
    raise UploadNotFound unless exists?

    JSON.parse(File.read(state_path))
  end

  def append_chunk!(expected_offset:, chunk_io:)
    current = state
    expected = Integer(expected_offset)
    actual = Integer(current.fetch("offset"))
    raise OffsetMismatch if expected != actual

    FileUtils.mkdir_p(base_dir)
    File.open(payload_path, "ab") do |file|
      IO.copy_stream(chunk_io, file)
    end

    new_offset = File.exist?(payload_path) ? File.size(payload_path) : 0
    write_state(current.merge("offset" => new_offset))
    new_offset
  end

  def with_input_io
    raise UploadNotFound unless File.exist?(payload_path)

    File.open(payload_path, "rb") do |file|
      yield file
    end
  end

  def delete!
    FileUtils.rm_f(payload_path)
    FileUtils.rm_f(state_path)
  end

  def write_state(data)
    FileUtils.mkdir_p(base_dir)
    File.write(state_path, JSON.generate(data))
  end

  private

  def normalize_upload_id(upload_id)
    value = upload_id.to_s.downcase
    raise InvalidUploadId unless value.match?(UPLOAD_ID_PATTERN)

    value
  end

  def base_dir
    File.join(StorageManager.instance.tmpdir, "tus_uploads")
  end

  def state_path
    File.join(base_dir, "#{upload_id}.json")
  end

  def payload_path
    File.join(base_dir, "#{upload_id}.bin")
  end
end
