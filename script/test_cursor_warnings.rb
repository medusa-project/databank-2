#!/usr/bin/env ruby

# Test script to capture cursor pagination warnings during import
# Run with: CURSOR_WARNING_CAPTURE=1 RAILS_ENV=development bin/rails runner script/test_cursor_warnings.rb

require_relative '../config/environment'
require 'fileutils'

puts "Starting cursor pagination warning capture test..."

# Create test bundle directory
test_dir = Rails.root.join('tmp', 'test_cursor_warnings')
FileUtils.rm_rf(test_dir)
FileUtils.mkdir_p(test_dir)

# Create minimal test datasets with creators
datasets = [
  {
    "key" => "TEST-CURSOR-001",
    "title" => "Test Dataset 1 - Cursor Warning Test",
    "description" => "First test dataset with creators to trigger cursor pagination warning",
    "identifier" => "10.13012/TEST-CURSOR-001",
    "owner_uid" => "test-owner",
    "depositor_name" => "Test User",
    "depositor_email" => "test@example.edu",
    "publication_state" => "draft",
    "created_at" => "2026-06-30T10:00:00Z",
    "updated_at" => "2026-06-30T10:00:00Z",
    "creators" => [
      {
        "name" => "Primary Creator",
        "position" => 1,
        "row_position" => 1,
        "contact" => true,
        "is_contact" => true,
        "created_at" => "2026-06-30T10:00:00Z",
        "updated_at" => "2026-06-30T10:00:00Z"
      },
      {
        "name" => "Secondary Creator",
        "position" => 2,
        "row_position" => 2,
        "contact" => false,
        "created_at" => "2026-06-30T10:00:00Z",
        "updated_at" => "2026-06-30T10:00:00Z"
      }
    ]
  },
  {
    "key" => "TEST-CURSOR-002",
    "title" => "Test Dataset 2 - Cursor Warning Test",
    "description" => "Second test dataset with creators",
    "identifier" => "10.13012/TEST-CURSOR-002",
    "owner_uid" => "test-owner",
    "depositor_name" => "Test User",
    "depositor_email" => "test@example.edu",
    "publication_state" => "published",
    "created_at" => "2026-06-30T11:00:00Z",
    "updated_at" => "2026-06-30T11:00:00Z",
    "creators" => [
      {
        "name" => "Another Creator",
        "position" => 1,
        "row_position" => 1,
        "contact" => true,
        "is_contact" => true,
        "created_at" => "2026-06-30T11:00:00Z",
        "updated_at" => "2026-06-30T11:00:00Z"
      }
    ]
  }
]

# Write datasets to bundle file
bundle_path = test_dir.join('test_bundle.ndjson')
File.open(bundle_path, 'w') do |f|
  datasets.each do |dataset|
    f.puts dataset.to_json
  end
end

puts "Created test bundle: #{bundle_path}"
puts "Bundle contains #{datasets.length} datasets\n"

# Create manifest
manifest = {
  "record_count" => datasets.length,
  "export_timestamp" => Time.current.iso8601
}
manifest_path = test_dir.join('manifest.json')
File.write(manifest_path, manifest.to_json)

# Create checksums
require 'digest'
bundle_content = File.read(bundle_path)
bundle_checksum = Digest::SHA256.hexdigest(bundle_content)
File.write(test_dir.join('test_bundle.ndjson.sha256'), bundle_checksum)

puts "Starting import with warning capture enabled...\n"
puts "=" * 80

# Clear previous warnings if the capture module exists
if defined?(CursorPaginationWarningCapture)
  CursorPaginationWarningCapture.clear
end

# Run the import
service = Migration::BundleImportService.new(
  bundle_path: bundle_path.to_s,
  checksum_path: test_dir.join('test_bundle.ndjson.sha256').to_s,
  manifest_path: manifest_path.to_s,
  report_path: test_dir.join('import_report.json').to_s
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

if defined?(CursorPaginationWarningCapture)
  warnings = CursorPaginationWarningCapture.warnings
  puts "\n" + "=" * 80
  puts "CURSOR PAGINATION WARNINGS CAPTURED: #{warnings.length}"
  puts "=" * 80
  if warnings.any?
    warnings.each_with_index do |warning, idx|
      puts "\nWarning #{idx + 1}:"
      puts warning[:backtrace].first(5).join("\n")
    end
  else
    puts "✓ NO WARNINGS CAPTURED - FIX IS WORKING!"
  end
else
  puts "\n⚠ Warning capture module not loaded. Set CURSOR_WARNING_CAPTURE=1"
end

# Cleanup
FileUtils.rm_rf(test_dir)
puts "\n✓ Test complete. Cleaned up temporary files."
