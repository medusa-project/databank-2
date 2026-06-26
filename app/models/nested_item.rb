# frozen_string_literal: true

##
# Represents a nested item, which is a unit of extracted content for archive files such as zip, tar, etc.
#
# == Attributes
#
# * +datafile_id+ - the id of the datafile that contains this nested item
# * +parent_id+ - the id of the parent nested item
# * +item_name+ - the name of the nested item
# * +media_type+ - the media type of the nested item
# * +size+ - the size of the nested item
# * +item_path+ - the path of the nested item
# * +is_directory+ - a boolean indicating whether the nested item is a directory

class NestedItem < ApplicationRecord
  belongs_to :datafile
  belongs_to :parent, class_name: "NestedItem", optional: true
  has_many :children, class_name: "NestedItem", foreign_key: "parent_id", dependent: :destroy

  validates :item_name, presence: true
  validates :datafile_id, presence: true
end
