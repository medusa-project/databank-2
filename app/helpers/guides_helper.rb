module GuidesHelper
  def guide_anchor_id(record)
    anchor = record.anchor.to_s.strip
    return anchor if anchor.present?

    "#{record.class.name.demodulize.underscore}-#{record.id}"
  end

  def guide_nav_label(record)
    record.label.presence || record.heading.presence || guide_anchor_id(record).tr("-", " ").titleize
  end
end
