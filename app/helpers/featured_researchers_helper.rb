module FeaturedResearchersHelper
  SPOTLIGHT_ALLOWED_TAGS = %w[p br ul ol li em strong b i blockquote a].freeze
  SPOTLIGHT_ALLOWED_ATTRIBUTES = %w[href title target rel].freeze

  def spotlight_rich_text(content)
    sanitize(content.to_s, tags: SPOTLIGHT_ALLOWED_TAGS, attributes: SPOTLIGHT_ALLOWED_ATTRIBUTES)
  end
end
