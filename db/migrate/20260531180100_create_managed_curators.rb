class CreateManagedCurators < ActiveRecord::Migration[8.0]
  def change
    create_table :managed_curators do |t|
      t.string :email, null: false

      t.timestamps
    end

    add_index :managed_curators, :email, unique: true
  end
end
