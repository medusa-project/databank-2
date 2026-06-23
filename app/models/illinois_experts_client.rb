# frozen_string_literal: true

require "cgi"
require "net/http"
require "nokogiri"

class IllinoisExpertsClient
  include ActiveModel::Conversion
  include ActiveModel::Naming

  def self.person_xml_doc(email)
    raise ArgumentError, "must provide email address string" if email.blank?

    endpoint = IdbConfig.fetch(:illinois_experts, :endpoint, default: "").to_s
    key = IdbConfig.fetch(:illinois_experts, :key, default: "").to_s
    return nil if endpoint.blank? || key.blank?

    stripped_email = email.strip
    encoded_email = CGI.escape(stripped_email)
    uri = URI.parse("#{endpoint}/persons/#{encoded_email}?apiKey=#{key}")

    return nil unless uri.respond_to?(:request_uri)

    request = Net::HTTP::Get.new(uri.request_uri)
    sock = Net::HTTP.new(uri.host, uri.port)
    sock.use_ssl = true

    begin
      response = sock.start { |http| http.request(request) }
    rescue Net::HTTPBadResponse, Net::HTTPServerError, SocketError, IOError, SystemCallError
      return nil
    end

    case response
    when Net::HTTPSuccess, Net::HTTPCreated, Net::HTTPRedirection
      begin
        doc = Nokogiri::XML(response.body)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError
        nil
      end
    end
  end

  def self.persons(email)
    person_doc = person_xml_doc(email)
    return nil if person_doc.nil?

    person_doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
  end

  def self.example
    endpoint = IdbConfig.fetch(:illinois_experts, :endpoint, default: "").to_s
    key = IdbConfig.fetch(:illinois_experts, :key, default: "").to_s
    return nil if endpoint.blank? || key.blank?

    uri = URI.parse("#{endpoint}/datasets")

    request = Net::HTTP::Get.new(uri.request_uri)
    request.add_field("api-key", key)

    sock = Net::HTTP.new(uri.host, uri.port)
    sock.use_ssl = true

    begin
      response = sock.start { |http| http.request(request) }
    rescue Net::HTTPBadResponse, Net::HTTPServerError, SocketError, IOError, SystemCallError
      return nil
    end

    case response
    when Net::HTTPSuccess, Net::HTTPCreated, Net::HTTPRedirection
      response.body
    end
  end
end
