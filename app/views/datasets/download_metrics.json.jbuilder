json.dataset_downloads do
  json.doi @dataset.identifier
  json.dataset_total_downloads @dataset.total_downloads
  json.dataset_download_tallies @dataset.dataset_download_tallies, :download_date, :tally

  json.files @dataset.datafiles.order(:id) do |datafile|
    json.filename datafile.binary_name
    json.file_total_downloads datafile.total_downloads
    json.file_download_tallies FileDownloadTally.where(file_web_id: datafile.web_id), :download_date, :tally
  end
end
