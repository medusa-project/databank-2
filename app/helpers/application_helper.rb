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
    secondary: {
      label: "Secondary",
      variant: "secondary",
      icon: "minus",
      icon_style: :solid
    },
    preview: {
      label: "Preview",
      variant: "secondary",
      icon: "eye",
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
      icon: "table-cells",
      icon_style: :solid
    },
    article: {
      label: "Article",
      variant: "primary",
      icon: "newspaper",
      icon_style: :regular
    },
    new: {
      label: "New",
      variant: "primary",
      icon: "plus",
      icon_style: :solid
    },
    cancel: {
      label: "Cancel",
      variant: "danger",
      icon: "xmark",
      icon_style: :solid
    },
    submit: {
      label: "Submit",
      variant: "primary",
      icon: "check-to-slot",
      icon_style: :solid
    },
    help: {
      label: "Get Help",
      variant: "secondary",
      icon: "question-circle",
      icon_style: :regular
    },
    delete: {
      label: "Delete",
      variant: "danger",
      icon: "trash",
      icon_style: :regular
    },
    up: {
      label: "Up",
      variant: "secondary",
      icon: "arrow-up",
      icon_style: :solid
    },
    down: {
      label: "Down",
      variant: "secondary",
      icon: "arrow-down",
      icon_style: :solid
    },
    back: {
      label: "Back",
      variant: "primary",
      icon: "arrow-left",
      icon_style: :solid
    },
    add: {
      label: "Add",
      variant: "primary",
      icon: "plus",
      icon_style: :solid
    },
    remove: {
      label: "Remove",
      variant: "danger",
      icon: "minus",
      icon_style: :solid
    },
    copy: {
      label: "Copy",
      variant: "secondary",
      icon: "copy",
      icon_style: :regular
    },
    report_back_to_search: {
      label: "Go back to search",
      variant: "secondary",
      icon: "caret-left",
      icon_style: :solid
    },
    report_print: {
      label: "Print",
      variant: "success",
      icon: "print",
      icon_style: :solid
    },
    report_download: {
      label: "Download",
      variant: "primary",
      icon: "circle-down",
      icon_style: :solid
    },
    download: {
      label: "Download",
      variant: "primary",
      icon: "download",
      icon_style: :solid
    },
    regenerate: {
      label: "Regenerate",
      variant: "primary",
      icon: "arrow-rotate-right",
      icon_style: :solid
    },
    admin_tools: {
      label: "Admin Tools",
      variant: "primary",
      icon: "wrench",
      icon_style: :solid
    },
    metrics: {
      label: "Metrics",
      variant: "primary",
      icon: "chart-simple",
      icon_style: :solid
    }
  }.freeze

  IDB_SEMANTIC_BADGES = {
    count: {
      label: nil,
      tone: "info",
      icon: "hashtag",
      icon_style: :solid
    },
    status_ok: {
      label: "OK",
      tone: "success",
      icon: "circle-check",
      icon_style: :solid
    },
    status_warning: {
      label: "Warning",
      tone: "warning",
      icon: "triangle-exclamation",
      icon_style: :solid
    },
    status_alert: {
      label: "Alert",
      tone: "danger",
      icon: "circle-xmark",
      icon_style: :solid
    },
    status_info: {
      label: "Info",
      tone: "info",
      icon: "circle-info",
      icon_style: :solid
    },
    neutral: {
      label: "Note",
      tone: "neutral",
      icon: nil,
      icon_style: :solid
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

  def contextual_help_link(prompt:, url:, new_tab: true, icon: "question-circle", icon_style: :regular, **html_options)
    classes = [ "idb-inline-help", html_options.delete(:class) ]
    html_options[:class] = classes.compact.join(" ")

    if new_tab
      html_options[:target] ||= "_blank"
      rel_values = html_options[:rel].to_s.split
      rel_values << "noopener"
      html_options[:rel] = rel_values.uniq.join(" ")
      html_options["aria-label"] ||= "#{prompt} Opens in a new tab."
    else
      html_options["aria-label"] ||= prompt
    end

    content = safe_join(
      [
        semantic_button_icon(icon, style: icon_style),
        tag.span(prompt, class: "idb-inline-help__label")
      ],
      " "
    )

    link_to(content, url, html_options)
  end

  def semantic_action_button(action:, url: nil, label: nil, icon: nil, icon_style: nil, icon_position: :left, icon_only: false, aria_label: nil, style: :legacy, type: "button", method: :get, **html_options)
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
      if method.to_sym == :post
        button_to(content, url, method: :post, **html_options)
      else
        link_to(content, url, html_options)
      end
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

  def semantic_badge(kind:, label: nil, value: nil, tone: nil, icon: nil, icon_style: nil, sr_label: nil, **html_options)
    badge_key = kind.to_sym
    defaults = IDB_SEMANTIC_BADGES.fetch(badge_key)

    resolved_tone = (tone.presence || defaults[:tone]).to_s
    resolved_icon = if icon == false
      nil
    else
      icon.presence || defaults[:icon]
    end
    resolved_icon_style = icon_style.presence || defaults[:icon_style] || :solid
    resolved_label = label.presence || defaults[:label]

    classes = [
      "idb-badge",
      "idb-badge--#{resolved_tone}",
      html_options.delete(:class)
    ]
    html_options[:class] = classes.compact.join(" ")

    visible_text = [ resolved_label, value ].compact.join(" ").strip
    content_segments = []
    content_segments << semantic_button_icon(resolved_icon, style: resolved_icon_style) if resolved_icon.present?
    content_segments << tag.span(visible_text, class: "idb-badge-label") if visible_text.present?

    if sr_label.present?
      content_segments << tag.span(sr_label, class: "sr-only")
      html_options["aria-label"] = sr_label
    end

    tag.span(safe_join(content_segments, " "), **html_options)
  end

  def semantic_count_badge(count:, label: nil, tone: "info", sr_label: nil, **html_options)
    semantic_badge(
      kind: :count,
      label: label,
      value: count,
      tone: tone,
      sr_label: sr_label,
      **html_options
    )
  end

  def semantic_status_badge(status:, label: nil, sr_label: nil, **html_options)
    normalized_status = status.to_s.strip.downcase
    kind = case normalized_status
    when "ok", "success", "succeeded", "approved", "published", "active", "available", "complete", "completed"
      :status_ok
    when "pending", "queued", "requested", "in_progress", "processing", "retrying", "started", "running", "generating"
      :status_warning
    when "failed", "error", "rejected", "invalid", "timeout", "orphaned"
      :status_alert
    when "skipped", "not_published", "unpublished", "inactive", "draft"
      :neutral
    else
      :status_info
    end

    resolved_label = label.presence || normalized_status.tr("_", " ")
    semantic_badge(kind: kind, label: resolved_label, sr_label: sr_label, **html_options)
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
