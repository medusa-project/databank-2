class AddPeekFieldsToDatafiles < ActiveRecord::Migration[8.1]
  def change
    add_column :datafiles, :peek_type, :string
    add_column :datafiles, :peek_content, :text

    add_index :datafiles, :peek_type
  end
end
