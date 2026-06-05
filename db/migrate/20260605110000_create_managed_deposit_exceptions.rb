class CreateManagedDepositExceptions < ActiveRecord::Migration[8.1]
  def change
    create_table :managed_deposit_exceptions do |t|
      t.string :email, null: false

      t.timestamps
    end

    add_index :managed_deposit_exceptions, :email, unique: true
  end
end
