# frozen_string_literal: true

##
# Datafile::Viewable
# ------------------
# This module is included in the Datafile model to provide methods for handling the preview of the datafile
# in the UI. It sets the datafile's preview type and text, based on the datafile's mime type.
# It also provides methods for determining the preview type of the datafile.
# The methods in this module are used in the datafile controller and views.

module Datafile::Viewable
  extend ActiveSupport::Concern

  class_methods do
    ##
    # Return the datafiles peek type based on its mime type and size
    # @param [String] mime_type the datafile's mime type
    # @param [Integer] num_bytes the number of bytes in the binary object
    # @return [String] the datafile's peek type
    def peek_type_from_mime(mime_type, num_bytes)
      return "none" unless num_bytes && mime_type && !mime_type.empty?

      mime_parts = mime_type.split("/")
      return "none" unless mime_parts.length == 2

      return "markdown" if mime_parts[0] == "markdown"

      text_subtypes = [ "csv", "xml", "x-sh", "x-javascript", "json", "r", "rb" ]
      supported_image_subtypes = [ "jp2", "jpeg", "dicom", "gif", "png", "bmp" ]
      archive_subtypes = [ "x-zip-compressed",
                          "zip",
                          "x-7z-compressed",
                          "x-rar-compressed",
                          "x-tar",
                          "x-xz",
                          "x-gzip",
                          "gzip",
                          "x-rar",
                          "x-gtar" ]
      pdf_subtypes = [ "pdf", "x-pdf" ]
      microsoft_subtypes = [ "msword",
                            "vnd.openxmlformats-officedocument.wordprocessingml.document",
                            "vnd.openxmlformats-officedocument.wordprocessingml.template",
                            "vnd.ms-word.document.macroEnabled.12",
                            "vnd.ms-word.template.macroEnabled.12",
                            "vnd.ms-excel",
                            "vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                            "vnd.openxmlformats-officedocument.spreadsheetml.template",
                            "vnd.ms-excel.sheet.macroEnabled.12",
                            "vnd.ms-excel.template.macroEnabled.12",
                            "vnd.ms-excel.addin.macroEnabled.12",
                            "vnd.ms-excel.sheet.binary.macroEnabled.12",
                            "vnd.ms-powerpoint",
                            "vnd.openxmlformats-officedocument.presentationml.presentation",
                            "vnd.openxmlformats-officedocument.presentationml.template",
                            "vnd.openxmlformats-officedocument.presentationml.slideshow",
                            "vnd.ms-powerpoint.addin.macroEnabled.12",
                            "vnd.ms-powerpoint.presentation.macroEnabled.12",
                            "vnd.ms-powerpoint.template.macroEnabled.12",
                            "vnd.ms-powerpoint.slideshow.macroEnabled.12" ]

      subtype = mime_parts[1].downcase
      if mime_parts[0] == "text" || text_subtypes.include?(subtype)
        "text"
      elsif mime_parts[0] == "image"
        return "image" if supported_image_subtypes.include?(subtype)

        "none"
      elsif microsoft_subtypes.include?(subtype)
        "microsoft"
      elsif pdf_subtypes.include?(subtype)
        "pdf"
      elsif archive_subtypes.include?(subtype)
        "archive"
      else
        "none"
      end
    end
  end

  # Instance methods

  ##
  # @return [Boolean] true if the datafile is a markdown file
  def markdown?
    peek_type == "markdown"
  end

  ##
  # @return [Boolean] true if the datafile is an archive file
  def archive?
    peek_type == "archive"
  end

  ##
  # @return [Boolean] true if the datafile is a text file
  def text?
    peek_type == "text"
  end

  ##
  # @return [Boolean] true if the datafile is an image file
  def image?
    peek_type == "image"
  end

  ##
  # @return [Boolean] true if the datafile is a microsoft file that can be previewed in the browser
  def microsoft?
    peek_type == "microsoft"
  end

  ##
  # @return [Boolean] true if the datafile is a pdf file that can be previewed in the browser
  def pdf?
    peek_type == "pdf"
  end

  ##
  # @return [String] the url for the microsoft preview of the datafile
  def microsoft_preview_url
    return nil unless microsoft?

    preview_base = "https://view.officeapps.live.com/op/view.aspx?src"
    preview_ref = "https%3A%2F%2Fdatabank.illinois.edu%2Fdatafiles%2F#{web_id}%2Fview"
    "#{preview_base}=#{preview_ref}"
  end

  ##
  # Set peek_type based on content_type
  def set_peek_type
    self.peek_type = Datafile.peek_type_from_mime(content_type, binary_size)
  end
end
