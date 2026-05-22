class AddLegacyDepositParityFields < ActiveRecord::Migration[8.1]
  def change
    change_table :datasets, bulk: true do |t|
      t.string :corresponding_creator_name
      t.string :corresponding_creator_email
      t.string :have_permission
      t.string :removed_private
      t.string :agree
      t.boolean :org_creators, null: false, default: false
      t.datetime :nested_updated_at
    end

    change_table :creators, bulk: true do |t|
      t.string :family_name
      t.string :given_name
      t.string :institution_name
      t.string :identifier
      t.string :identifier_scheme
      t.integer :type_of
      t.integer :row_position
      t.integer :row_order
      t.boolean :is_contact, null: false, default: false
    end

    change_table :contributors, bulk: true do |t|
      t.string :family_name
      t.string :given_name
      t.string :institution_name
      t.string :identifier
      t.string :identifier_scheme
      t.integer :type_of
      t.integer :row_position
      t.integer :row_order
      t.boolean :is_contact, null: false, default: false
    end

    change_table :funders, bulk: true do |t|
      t.string :code
      t.string :grant
      t.string :identifier_scheme
      t.integer :row_position
    end

    change_table :related_materials, bulk: true do |t|
      t.string :material_type
      t.string :selected_type
      t.string :availability
      t.string :link
      t.string :uri_type
      t.text :citation
      t.string :datacite_list
      t.text :note
      t.boolean :feature, null: false, default: false
      t.integer :row_position
    end

    add_column :datafiles, :row_position, :integer
  end
end
