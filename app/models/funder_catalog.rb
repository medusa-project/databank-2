class FunderCatalog
  Entry = Struct.new(:code, :name, :identifier, :display_position, :identifier_scheme, keyword_init: true)

  OTHER_CODE = "other".freeze

  ENTRIES = [
    Entry.new(code: "IDCEO", name: "Illinois Department of Commerce & Economic Opportunity (DCEO)", identifier: "10.13039/100004885", display_position: 10, identifier_scheme: "DOI"),
    Entry.new(code: "IDHS", name: "Illinois Department of Human Services (DHS)", identifier: "10.13039/100004886", display_position: 20, identifier_scheme: "DOI"),
    Entry.new(code: "IDNR", name: "Illinois Department of Natural Resources (IDNR)", identifier: "10.13039/100004887", display_position: 30, identifier_scheme: "DOI"),
    Entry.new(code: "IDOT", name: "Illinois Department of Transportation (IDOT)", identifier: "10.13039/100009637", display_position: 40, identifier_scheme: "DOI"),
    Entry.new(code: "USARMY", name: "U.S. Army", identifier: "10.13039/100006751", display_position: 50, identifier_scheme: "DOI"),
    Entry.new(code: "USDA", name: "U.S. Department of Agriculture (USDA)", identifier: "10.13039/100000199", display_position: 60, identifier_scheme: "DOI"),
    Entry.new(code: "DOE", name: "U.S. Department of Energy (DOE)", identifier: "10.13039/100000015", display_position: 70, identifier_scheme: "DOI"),
    Entry.new(code: "USGS", name: "U.S. Geological Survey (USGS)", identifier: "10.13039/100000203", display_position: 80, identifier_scheme: "DOI"),
    Entry.new(code: "NASA", name: "U.S. National Aeronautics and Space Administration (NASA)", identifier: "10.13039/100000104", display_position: 90, identifier_scheme: "DOI"),
    Entry.new(code: "NIH", name: "U.S. National Institutes of Health (NIH)", identifier: "10.13039/100000002", display_position: 100, identifier_scheme: "DOI"),
    Entry.new(code: "NSF", name: "U.S. National Science Foundation (NSF)", identifier: "10.13039/100000001", display_position: 110, identifier_scheme: "DOI"),
    Entry.new(code: OTHER_CODE, name: "Other -- Please provide name:", identifier: "", display_position: 1000, identifier_scheme: "")
  ].freeze

  def self.entries
    ENTRIES
  end

  def self.known_entries
    ENTRIES.reject { |entry| entry.code == OTHER_CODE }.sort_by(&:display_position)
  end

  def self.known_names
    known_entries.map(&:name)
  end

  def self.identifier_map
    known_entries.each_with_object({}) do |entry, map|
      map[entry.name] = entry.identifier
    end
  end
end
