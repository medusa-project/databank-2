require 'json'
require 'fileutils'

# Create a minimal test bundle with just the first 3 datasets from the real bundle
real_bundle = Rails.root.join('migration_bundles', 'dataset_20260626T185934Z', 'legacy_datasets.ndjson')

test_dir = Rails.root.join('tmp', 'test_real_bundle_overwrite')
FileUtils.rm_rf(test_dir)
FileUtils.mkdir_p(test_dir)

test_bundle_path = test_dir.join('test_bundle.ndjson')

# Extract first 3 datasets from real bundle
puts "Extracting first 3 datasets from real migration bundle..."
line_count = 0
File.open(test_bundle_path, 'w') do |out|
  File.foreach(real_bundle) do |line|
    break if line_count >= 3
    out.puts(line)
    line_count += 1
  end
end

puts "Created test bundle with #{line_count} datasets at: #{test_bundle_path}"

# Create manifest
manifest = {
  "record_count" => line_count,
  "export_timestamp" => Time.current.iso8601
}
manifest_path = test_dir.join('manifest.json')
File.write(manifest_path, manifest.to_json)

# Create checksums
require 'digest'
bundle_content = File.read(test_bundle_path)
bundle_checksum = Digest::SHA256.hexdigest(bundle_content)
File.write(test_dir.join('test_bundle.ndjson.sha256'), bundle_checksum)

puts "\nStarting import test with OVERWRITE=true and warning capture..."
puts "=" * 80

# Run the import with overwrite to force record processing
begin
  service = Migration::BundleImportService.new(
    bundle_path: test_bundle_path.to_s,
    checksum_path: test_dir.join('test_bundle.ndjson.sha256').to_s,
    manifest_path: manifest_path.to_s,
    report_path: test_dir.join('import_report.json').to_s,
    overwrite: true  # Force overwrite to trigger saves
  )

  result = service.call

  puts "\n" + "=" * 80
  puts "IMPORT RESULTS"
  puts "=" * 80
  puts "Status: #{result[:validation_error].present? ? 'FAILED' : 'SUCCESS'}"
  puts "Created: #{result[:created]}"
  puts "Updated: #{result[:updated]}"
  puts "Skipped: #{result[:skipped_existing]}"
  puts "Failed: #{result[:failed]}"
  puts "Error: #{result[:validation_error]}" if result[:validation_error]

  if defined?(CursorPaginationWarningCapture)
    warnings = CursorPaginationWarningCapture.warnings
    puts "\n" + "=" * 80
    puts "CURSOR PAGINATION WARNINGS CAPTURED: #{warnings.length}"
    puts "=" * 80
    if warnings.any?
      puts "⚠ WARNINGS FOUND! Details:"
      warnings.each_with_index do |warning, idx|
        puts "\n--- Warning #{idx + 1} ---"
        puts "Message: #{warning[:message]}"
        puts "Backtrace:"
        warning[:backtrace].first(8).each { |line| puts "  #{line}" }
      end
    else
      puts "✓ NO WARNINGS CAPTURED - FIX IS WORKING!"
    end
  else
    puts "⚠ Warning capture module not loaded"
  end
rescue => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.first(15).join("\n")
end

# Cleanup
FileUtils.rm_rf(test_dir)
puts "\n✓ Test complete."
