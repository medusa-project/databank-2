require 'json'
require 'fileutils'

# Create test dataset with minimal required fields
test_dir = Rails.root.join('tmp', 'test_import_debug')
FileUtils.rm_rf(test_dir)
FileUtils.mkdir_p(test_dir)

dataset = {
  "key" => "TEST001",
  "title" => "Test",
  "identifier" => "10.13012/TEST001",
  "owner_uid" => "test",
  "depositor_name" => "Test",
  "depositor_email" => "test@example.edu",
  "creators" => [
    { "name" => "Creator 1", "contact" => true, "created_at" => Time.current.iso8601, "updated_at" => Time.current.iso8601 }
  ]
}

bundle_path = test_dir.join('bundle.ndjson')
File.write(bundle_path, dataset.to_json + "\n")

puts "Testing with bundle: #{bundle_path}"

# Try the import directly
begin
  result = Migration::BundleImportService.new(bundle_path: bundle_path.to_s).call
  puts "\nImport result:"
  puts "  Created: #{result[:created]}"
  puts "  Updated: #{result[:updated]}"
  puts "  Skipped: #{result[:skipped_existing]}"
  puts "  Failed: #{result[:failed]}"
  puts "  Error: #{result[:validation_error]}" if result[:validation_error]

  # Check if dataset was created
  created = Dataset.find_by(key: "TEST001")
  if created
    puts "\n✓ Dataset created: #{created.key}"
    puts "  Creators: #{created.creators.count}"
    puts "  Corresponding creator name: #{created.corresponding_creator_name}"
  else
    puts "\n✗ Dataset not created"
  end
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(10).join("\n")
end
