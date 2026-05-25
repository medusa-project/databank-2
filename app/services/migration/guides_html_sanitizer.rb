require "rails/html/sanitizer"
require "loofah"

module Migration
  class GuidesHtmlSanitizer
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
          scrub_forbidden_protocol(node, "src")
        end

        fragment.to_html
      end

      def scrub_forbidden_protocol(node, attribute)
        value = node[attribute].to_s.strip.downcase
        return if value.blank?
        return unless FORBIDDEN_PROTOCOLS.any? { |prefix| value.start_with?(prefix) }

        node.remove_attribute(attribute)
      end
    end
  end
end
