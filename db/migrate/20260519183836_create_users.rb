class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :provider, null: false, default: "developer"
      t.string :uid,      null: false
      t.string :email,    null: false
      t.string :username
      t.string :name
      t.string :role,     null: false, default: "depositor"

      t.timestamps
    end
    add_index :users, %i[provider uid], unique: true
    add_index :users, :email, unique: true
  end
end
