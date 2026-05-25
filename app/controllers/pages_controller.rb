class PagesController < ApplicationController
  skip_before_action :authenticate_user!

  def deposit; end
  def policies; end
  def guides
    @guide_sections = Guide::Section
      .where(public: true)
      .includes(
        :rich_text_body,
        guide_items: [
          :rich_text_body,
          { guide_subitems: :rich_text_body }
        ]
      )
      .ordered
  end
  def contact; end
end
