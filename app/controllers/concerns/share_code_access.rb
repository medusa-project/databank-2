module ShareCodeAccess
  extend ActiveSupport::Concern

  included do
    helper_method :shared_access_params
  end

  private

  def grant_share_code_access(dataset:)
    @shared_by_link = dataset.valid_share_code?(code: params[:code])
    return unless @shared_by_link

    current_ability.can %i[read view_files], Dataset, id: dataset.id
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    response.set_header("Cache-Control", "no-store")
  end

  def shared_access_params
    @shared_by_link ? { code: params[:code] } : {}
  end
end
