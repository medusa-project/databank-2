module ApplicationHelper
  # Provides helper methods for generating semantic buttons with consistent styling and accessibility features.
  # Example usage:
  #   <%= semantic_action_button action: :save, url: save_path, label: "Save Changes", icon_only: true, aria_label: "Save changes to the
  #   dataset" %>
  #   This would generate a button with the "Save" label, a thumbtack icon, and appropriate classes for styling. The button would link to the specified URL and include an aria-label for accessibility when icon_only is true.
  #   The IDB_SEMANTIC_BUTTONS constant defines default configurations for common actions, which can be overridden by passing options to the helper method. The helper also includes validation to ensure that only safe URLs are used when generating links.
  #   The semantic_action_button method supports both link and button elements, depending on whether a URL is provided. It also allows for customization of the button style (legacy or idb), variant (primary, success, etc.), and icon position.
  #   The semantic_button_icon method generates the appropriate <i> tag for FontAwesome icons based on the specified style and icon name.
  #   The helper methods are designed to promote consistency across the application while also providing flexibility for different use cases.
  #   The dataset_persistent_url and dataset_plain_text_citation methods provide convenient ways to generate a DOI URL and a plain text citation for a given dataset, respectively. The dataset_primary_contact_name method retrieves the name of the primary contact creator for a dataset, if available.
  #   The external_https_link_to method ensures that only valid HTTPS URLs are used when generating external links, returning nil for invalid or unsafe URLs. The internal_link_to method can be used for generating links to internal paths without additional URL validation.
  #   The helper methods are intended to be used in views to simplify the generation of common UI elements and ensure that best practices for accessibility and security are followed.
  #   The IDB_SEMANTIC_BUTTONS constant can be easily extended to include additional actions as needed, providing a centralized configuration for button styles and icons throughout the application.
  #   The helper methods can be further customized or extended to support additional features, such as different icon libraries, more complex button layouts, or additional accessibility attributes as required by the application's design and user needs.
  #   Overall, the ApplicationHelper module serves as a central place for defining reusable view helper methods that enhance the consistency, accessibility, and maintainability of the application's user interface components.
  IDB_SEMANTIC_BUTTONS = {
    save: {
      label: "Save",
      variant: "primary",
      icon: "thumbtack",
      icon_style: :solid
    },
    edit: {
      label: "Edit",
      variant: "success",
      icon: "pen-to-square",
      icon_style: :regular
    },
    search: {
      label: "Search",
      variant: "success",
      icon: "magnifying-glass",
      icon_style: :solid
    },
    continue: {
      label: "Continue",
      variant: "primary",
      icon: "right-from-bracket",
      icon_style: :solid
    },
    publish: {
      label: "Publish",
      variant: "primary",
      icon: "paper-plane",
      icon_style: :regular
    },
    dataset: {
      label: "Dataset",
      variant: "primary",
      icon: "table-columns",
      icon_style: :solid
    },
    article: {
      label: "Article",
      variant: "primary",
      icon: "newspaper",
      icon_style: :regular
    }
  }.freeze

  def external_https_link_to(label:, url:, **options)
    safe_url = safe_https_url(url)
    return if safe_url.blank?

    link_to(label, safe_url, **options)
  end

  def internal_link_to(label:, relative_url:, **options)
    link_to(label, relative_url, **options)
  end

  def dataset_persistent_url(dataset)
    return if dataset.identifier.blank?

    "https://doi.org/#{dataset.identifier}"
  end

  def dataset_plain_text_citation(dataset)
    citation_parts = []
    creator_names = dataset.creators.map(&:name).reject(&:blank?)

    citation_parts << creator_names.join("; ") if creator_names.any?

    year = dataset.published_at&.year || dataset.updated_at&.year || dataset.created_at&.year
    citation_parts << "(#{year})" if year.present?
    citation_parts << "#{dataset.title}." if dataset.title.present?
    citation_parts << dataset.publisher if dataset.publisher.present?

    persistent_url = dataset_persistent_url(dataset)
    citation_parts << persistent_url if persistent_url.present?

    citation_parts.join(" ")
  end

  def dataset_primary_contact_name(dataset)
    dataset.creators.find(&:contact?)&.name
  end

  def semantic_action_button(action:, url: nil, label: nil, icon: nil, icon_style: nil, icon_position: :left, icon_only: false, aria_label: nil, style: :legacy, type: "button", **html_options)
    action_key = action.to_sym
    defaults = IDB_SEMANTIC_BUTTONS.fetch(action_key)

    button_label = label.presence || defaults[:label]
    icon_name = icon.presence || defaults[:icon]
    variant = defaults[:variant]
    framework_class = button_framework_class(style, variant)
    style_class = style.to_sym == :legacy ? "legacy-btn-with-icon" : "idb-button-with-icon"
    icon_only_class = style.to_sym == :legacy ? "legacy-btn-icon-only" : "idb-button-icon-only"

    classes = [ framework_class, style_class, html_options.delete(:class) ]
    classes << icon_only_class if icon_only
    html_options[:class] = classes.compact.join(" ")

    if icon_only
      html_options[:"aria-label"] = aria_label.presence || button_label
    end

    resolved_icon_style = icon_style.presence || defaults[:icon_style] || :regular
    resolved_icon_position = icon_position.to_sym

    unless %i[left right].include?(resolved_icon_position)
      raise ArgumentError, "Unsupported icon position: #{icon_position.inspect}"
    end

    icon_content = semantic_button_icon(icon_name, style: resolved_icon_style)
    label_content = (tag.span(button_label, class: "idb-button-label") unless icon_only)

    ordered_content = if icon_only || resolved_icon_position == :left
      [ icon_content, label_content ]
    else
      [ label_content, icon_content ]
    end

    content = safe_join(ordered_content.compact, " ")

    if url.present?
      link_to(content, url, html_options)
    else
      button_tag(content, { type: type }.merge(html_options))
    end
  end

  def semantic_button_icon(icon_name, style: :regular)
    style_class = {
      regular: "fa-regular",
      solid: "fa-solid",
      brands: "fa-brands"
    }.fetch(style.to_sym)

    tag.i(nil, class: [ "idb-button-icon", style_class, "fa-#{icon_name}" ].join(" "), "aria-hidden": "true")
  end

  private

  def button_framework_class(style, variant)
    case style.to_sym
    when :legacy
      "legacy-btn legacy-btn-#{variant}"
    when :idb
      "idb-button-#{variant}"
    else
      raise ArgumentError, "Unsupported button style: #{style.inspect}"
    end
  end

  def safe_https_url(url)
    uri = URI.parse(url.to_s)
    return if uri.scheme.blank? || !%w[http https].include?(uri.scheme.downcase) || uri.host.blank?

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
