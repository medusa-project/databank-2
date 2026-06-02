class Datafile < ApplicationRecord
  include Datafile::Storable

  WEB_ID_LENGTH = 5 unless const_defined?(:WEB_ID_LENGTH)

  belongs_to :dataset
  has_one_attached :binary

  validates :web_id,      presence: true, uniqueness: true,
                          format: { with: /\A[a-z0-9]{#{WEB_ID_LENGTH}}\z/ }
  validates :binary_name, presence: true, allow_blank: true

  before_validation :set_web_id, on: :create

  def to_param
    web_id
  end

  def sync_metadata_from_attachment!
    return unless binary.attached?

    self.binary_name = binary.filename.to_s
    self.binary_size = binary.byte_size
  end

  def total_downloads
    FileDownloadTally.where(file_web_id: web_id).sum(:tally)
  end

  def record_download(request_ip)
    return if request_ip.blank?
    return unless dataset.files_publicly_readable_now?
    return if dataset.identifier.blank?

    unless dataset.ip_downloaded_dataset_today(request_ip)
      dataset_tally = DatasetDownloadTally.find_or_initialize_by(
        dataset_key: dataset.key,
        download_date: Date.current
      )
      dataset_tally.doi = dataset.identifier
      dataset_tally.tally = dataset_tally.tally.to_i + 1
      dataset_tally.save!
    end

    return if ip_downloaded_file_today(request_ip)

    DayFileDownload.create!(
      ip_address: request_ip,
      download_date: Date.current,
      file_web_id: web_id,
      filename: binary_name,
      dataset_key: dataset.key,
      doi: dataset.identifier
    )

    file_tally = FileDownloadTally.find_or_initialize_by(
      file_web_id: web_id,
      download_date: Date.current
    )
    file_tally.dataset_key = dataset.key
    file_tally.doi = dataset.identifier
    file_tally.filename = binary_name
    file_tally.tally = file_tally.tally.to_i + 1
    file_tally.save!
  end

  def ip_downloaded_file_today(request_ip)
    DayFileDownload.where(
      ip_address: request_ip,
      file_web_id: web_id,
      download_date: Date.current
    ).exists?
  end

  private

  def set_web_id
    self.web_id ||= generate_web_id
  end

  def generate_web_id
    loop do
      candidate = (36**(WEB_ID_LENGTH - 1) + rand(36**WEB_ID_LENGTH - 36**(WEB_ID_LENGTH - 1))).to_s(36)
      break candidate unless self.class.exists?(web_id: candidate)
    end
  end
end
