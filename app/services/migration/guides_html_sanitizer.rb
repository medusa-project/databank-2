require "rails/html/sanitizer"
require "loofah"

module Migration
  class GuidesHtmlSanitizer
    LEGACY_IMAGE_SRC_MAP = {
      "/assets/biological_dataset-7cdd84a2397d72dad00cd89d7f521d009a661908256f72e1ce4778048e53b095.png" => "/assets/biological_dataset.png",
      "/assets/publication_supporting-9c4cb1f8500d64dfbe83fc793781a3087e6cfad9a2e5cc2b2da2be1e896baba4.png" => "/assets/publication_supporting.png",
      "/assets/temporal_grouping-e179baff356f5fac2c9d33ae8d492642ce7399d54a4c9a5fe05ac70eb0507edc.png" => "/assets/temporal_grouping.png"
    }.freeze

    ALLOWED_TAGS = %w[
      a p br hr div span strong em b i u small sup sub
      ul ol li
      h1 h2 h3 h4 h5 h6
      table thead tbody tfoot tr th td
      pre code blockquote
      details summary
      img
    ].freeze

    ALLOWED_ATTRIBUTES = %w[
      href src alt title class id target rel
      role
      colspan rowspan scope
      width height
      aria-label aria-controls aria-expanded aria-labelledby aria-multiselectable
    ].freeze

    FORBIDDEN_PROTOCOLS = [ "javascript:", "data:" ].freeze

    class << self
      def sanitize_html(html)
        return "" if html.blank?

        safe = sanitizer.sanitize(pruned_html(html.to_s), tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
        harden_links_and_urls(safe)
      end

      private

      def sanitizer
        @sanitizer ||= Rails::Html::SafeListSanitizer.new
      end

      def pruned_html(html)
        fragment = Loofah.fragment(html)
        fragment.css("script,style").each(&:remove)
        fragment.to_html
      end

      def harden_links_and_urls(html)
        fragment = Loofah.fragment(html)

        fragment.css("a").each do |node|
          scrub_forbidden_protocol(node, "href")

          next unless node["target"].to_s == "_blank"

          rel_tokens = node["rel"].to_s.split(/\s+/)
          rel_tokens |= %w[noopener noreferrer]
          node["rel"] = rel_tokens.join(" ").strip
        end

        fragment.css("img").each do |node|
          normalize_legacy_image_src(node)
          scrub_forbidden_protocol(node, "src")
          ensure_image_alt(node)
        end

        fragment.to_html
      end

      def scrub_forbidden_protocol(node, attribute)
        value = node[attribute].to_s.strip.downcase
        return if value.blank?
        return unless FORBIDDEN_PROTOCOLS.any? { |prefix| value.start_with?(prefix) }

        node.remove_attribute(attribute)
      end

      def normalize_legacy_image_src(node)
        src = node["src"].to_s.strip
        return if src.blank?

        replacement = LEGACY_IMAGE_SRC_MAP[src]
        node["src"] = replacement if replacement.present?
      end

      def ensure_image_alt(node)
        return if node["alt"].to_s.strip.present?

        src = node["src"].to_s
        basename = File.basename(src)
        stem = basename.sub(/\.[^.]+\z/, "")
        stem = stem.sub(/-[0-9a-f]{16,}\z/i, "")
        fallback = stem.tr("_", " ").tr("-", " ").squeeze(" ").strip
        node["alt"] = fallback.present? ? fallback.titleize : "Guide image"
      end
    end
  end
end
