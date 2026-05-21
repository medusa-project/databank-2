class DatasetVersionFileCopyService
  Result = Struct.new(:copied_count, :skipped_count, keyword_init: true)

  def initialize(version_dataset:)
    @version_dataset = version_dataset
  end

  def call
    previous = @version_dataset.previous_version_dataset
    raise ArgumentError, "previous version dataset not found" if previous.nil?

    copied = 0
    skipped = 0

    Datafile.transaction do
      previous.datafiles.find_each do |source_datafile|
        if duplicate_in_version?(source_datafile)
          skipped += 1
          next
        end

        copy_datafile!(source_datafile)
        copied += 1
      end
    end

    Result.new(copied_count: copied, skipped_count: skipped)
  end

  private

  def copy_datafile!(source)
    datafile = @version_dataset.datafiles.create!(
      binary_name: source.binary_name,
      binary_size: source.binary_size,
      description: source.description,
      storage_root: source.storage_root,
      storage_key: source.storage_key,
      medusa_id: source.medusa_id
    )

    return unless source.binary.attached?

    datafile.binary.attach(source.binary.blob)
    datafile.sync_metadata_from_attachment!
    datafile.save!
  end

  def duplicate_in_version?(source)
    if source.binary.attached?
      return @version_dataset.datafiles.joins(binary_attachment: :blob).exists?(active_storage_blobs: { id: source.binary.blob_id })
    end

    @version_dataset.datafiles.exists?(
      storage_root: source.storage_root,
      storage_key: source.storage_key,
      binary_name: source.binary_name,
      binary_size: source.binary_size
    )
  end
end
