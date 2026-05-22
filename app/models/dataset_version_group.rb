require "set"

class DatasetVersionGroup
  MAX_CHAIN_LENGTH = 50

  attr_reader :dataset, :entries, :latest_published_version

  def initialize(dataset)
    @dataset = dataset
    @entries = build_entries
    @latest_published_version = @entries.reverse.find { |entry| entry[:dataset].published? }&.fetch(:dataset)
  end

  private

  def build_entries
    seen_keys = Set.new([ dataset.key ])

    previous_entries = collect_previous_entries(seen_keys)
    next_entries = collect_next_entries(seen_keys)

    previous_entries.reverse + [ entry_for(dataset, selected: true) ] + next_entries
  end

  def collect_previous_entries(seen_keys)
    entries = []
    current = dataset
    count = 0

    while count < MAX_CHAIN_LENGTH
      previous = current.previous_version_dataset
      break if previous.nil?
      break if seen_keys.include?(previous.key)

      seen_keys << previous.key
      entries << entry_for(previous)
      current = previous
      count += 1
    end

    entries
  end

  def collect_next_entries(seen_keys)
    entries = []
    current = dataset
    count = 0

    while count < MAX_CHAIN_LENGTH
      nxt = current.next_version_dataset_any
      break if nxt.nil?
      break if seen_keys.include?(nxt.key)

      seen_keys << nxt.key
      entries << entry_for(nxt)
      current = nxt
      count += 1
    end

    entries
  end

  def entry_for(record, selected: false)
    {
      dataset: record,
      key: record.key,
      title: record.title,
      doi: record.identifier,
      publication_state: record.publication_state,
      selected: selected
    }
  end
end
