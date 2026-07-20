#!/usr/bin/env ruby
# Create a small test bundle for quick import testing
# Includes datasets with complex nested items

require 'json'
require 'fileutils'

BUNDLE_ROOT = ARGV[0] || '/workspaces/databank-2/migration_bundles'
OUTPUT_DIR = '/workspaces/databank-2/test_bundle'

def count_nested_items(items)
  items.reduce(0) do |sum, item|
    sum + 1 + (count_nested_items(item['children'] || []))
  end
end

puts "Creating test bundle from #{BUNDLE_ROOT}..."
FileUtils.rm_rf(OUTPUT_DIR)
FileUtils.mkdir_p(OUTPUT_DIR)

# Track what to include
dataset_keys = Set.new
user_uids = Set.new

# Find 2-3 datasets with interesting nested items
puts "Scanning datasets..."
datasets_file = File.join(BUNDLE_ROOT, 'dataset_20260626T185934Z/legacy_datasets.ndjson')
test_datasets = []

File.open(datasets_file).each_line do |line|
  dataset = JSON.parse(line)
  datafiles = dataset['datafiles'] || []

  # Check for nested items
  has_nested = datafiles.any? { |df| df['nested_items']&.any? }

  if has_nested
    nested_count = datafiles.map { |df| count_nested_items(df['nested_items'] || []) }.sum
    test_datasets << {
      key: dataset['key'],
      title: dataset['title'],
      nested_count: nested_count,
      data: dataset
    }
  end

  break if test_datasets.length >= 3
end

if test_datasets.empty?
  puts "No datasets with nested items found, using first few datasets..."
  File.open(datasets_file).each_line do |line|
    dataset = JSON.parse(line)
    test_datasets << { key: dataset['key'], data: dataset }
    break if test_datasets.length >= 2
  end
end

puts "Found #{test_datasets.length} test datasets"
test_datasets.each { |d| title = d[:title] ? d[:title].slice(0, 50) : ""; puts "  - #{d[:key]}: #{title} (#{d[:nested_count]&.to_s || '0'} nested items)" }

# Extract dataset keys and user UIDs
test_datasets.each do |item|
  dataset_keys << item[:data]['key']
  user_uids << item[:data]['owner_uid']
  user_uids << item[:data]['depositor_name']
  (item[:data]['creators'] || []).each { |c| user_uids << c['name'] }
  (item[:data]['contributors'] || []).each { |c| user_uids << c['name'] }
end

puts "\nExtracting data for #{dataset_keys.size} datasets..."

# Create dataset directory and copy filtered datasets
dataset_dir = File.join(OUTPUT_DIR, 'dataset_20260626T185934Z')
FileUtils.mkdir_p(dataset_dir)
out_file = File.join(dataset_dir, 'legacy_datasets.ndjson')
File.open(out_file, 'w') do |out|
  File.open(datasets_file).each_line do |line|
    dataset = JSON.parse(line)
    if dataset_keys.include?(dataset['key'])
      out.puts(line)
    end
  end
end
puts "✓ #{out_file}"

# Create users directory and copy filtered users
users_src = File.join(BUNDLE_ROOT, 'users_20260626T185934Z/legacy_users.ndjson')
users_dir = File.join(OUTPUT_DIR, 'users_20260626T185934Z')
FileUtils.mkdir_p(users_dir)
user_out = File.join(users_dir, 'legacy_users.ndjson')
user_count = 0
File.open(user_out, 'w') do |out|
  File.open(users_src).each_line do |line|
    user = JSON.parse(line)
    if user_uids.include?(user['uid']) || user_count < 5
      out.puts(line)
      user_uids.delete(user['uid'])
      user_count += 1
    end
  end
end
puts "✓ #{user_out} (#{user_count} users)"

# Copy other bundle files (smaller ones) with their directory structure
[
  [ 'audit_20260626T190145Z', 'legacy_audits.ndjson', 100 ],
  [ 'permissions_20260626T190135Z', 'legacy_permissions.ndjson', 100 ],
  [ 'dataset_access_grants_20260626T190135Z', 'legacy_dataset_access_grants.ndjson', 100 ],
  [ 'guide_20260626T190137Z', 'legacy_guides.ndjson', 50 ],
  [ 'spotlight_20260626T190137Z', 'legacy_featured_researchers.ndjson', 50 ],
  [ 'medusa_ingests_20260626T190137Z', 'legacy_medusa_ingests.ndjson', 50 ],
  [ 'download_metrics_20260626T190145Z', 'legacy_download_metrics.ndjson', 50 ]
].each do |dir_name, file_name, max_lines|
  src = File.join(BUNDLE_ROOT, dir_name, file_name)
  next unless File.exist?(src)

  out_dir = File.join(OUTPUT_DIR, dir_name)
  FileUtils.mkdir_p(out_dir)
  out_file = File.join(out_dir, file_name)
  count = 0
  File.open(out_file, 'w') do |out|
    File.open(src).each_line do |line|
      out.puts(line)
      count += 1
      break if count >= max_lines
    end
  end
  puts "✓ #{out_file} (#{count} lines)"
end

puts "\n✅ Test bundle created at #{OUTPUT_DIR}"
puts "\nTo test:"
puts "  cd /workspaces/databank-2"
puts "  BUNDLE_ROOT=#{OUTPUT_DIR} bundle exec rails cutover:import_all"
