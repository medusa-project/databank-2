class CreatorsController < ApplicationController
  require "net/http"
  require "json"

  before_action :set_dataset
  before_action :set_creator, only: %i[update destroy]

  def orcid_lookup
    family_name = params[:family_name].to_s.strip
    given_name = params[:given_name].to_s.strip

    if family_name.blank? && given_name.blank?
      render json: { error: "Provide family_name or given_name" }, status: :unprocessable_entity
      return
    end

    query_parts = []
    query_parts << "family-name:#{family_name}*" if family_name.present?
    query_parts << "given-names:#{given_name}*" if given_name.present?
    query = query_parts.join(" AND ")

    uri = URI("https://pub.orcid.org/v3.0/expanded-search/")
    uri.query = URI.encode_www_form(q: query)

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      render json: { error: "ORCID lookup unavailable" }, status: :bad_gateway
      return
    end

    payload = JSON.parse(response.body)
    results = Array(payload["expanded-result"]).first(10).map do |entry|
      {
        orcid: entry["orcid-id"],
        family_name: entry["family-names"],
        given_name: entry["given-names"],
        institution: entry["institution-name"]
      }
    end

    render json: { results: results }
  rescue JSON::ParserError, StandardError => e
    Rails.logger.error("ORCID lookup failed for dataset #{@dataset.key}: #{e.class}: #{e.message}")
    render json: { error: "ORCID lookup unavailable" }, status: :bad_gateway
  end

  def create
    @creator = @dataset.creators.build(creator_params)

    if @creator.save
      redirect_to edit_dataset_path(@dataset), notice: "Creator added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @creator.errors.full_messages.to_sentence
    end
  end

  def update
    if @creator.update(creator_params)
      redirect_to edit_dataset_path(@dataset), notice: "Creator updated."
    else
      redirect_to edit_dataset_path(@dataset), alert: @creator.errors.full_messages.to_sentence
    end
  end

  def destroy
    @creator.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "Creator removed."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset
  end

  def set_creator
    @creator = @dataset.creators.find(params[:id])
  end

  def creator_params
    params.require(:creator).permit(
      :name,
      :family_name,
      :given_name,
      :institution_name,
      :identifier,
      :identifier_scheme,
      :type_of,
      :email,
      :contact,
      :is_contact,
      :position,
      :row_position,
      :row_order
    )
  end
end
