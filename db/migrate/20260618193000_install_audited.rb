class InstallAudited < ActiveRecord::Migration[8.1]
  def up
    create_table :audits do |t|
      t.integer :auditable_id
      t.string :auditable_type
      t.integer :associated_id
      t.string :associated_type
      t.integer :user_id
      t.string :user_type
      t.string :username
      t.string :action
      t.jsonb :audited_changes
      t.integer :version, default: 0
      t.string :comment
      t.string :remote_address
      t.string :request_uuid
      t.datetime :created_at
    end

    add_index :audits, %i[auditable_id auditable_type], name: "auditable_index"
    add_index :audits, %i[associated_id associated_type], name: "associated_index"
    add_index :audits, %i[user_id user_type], name: "user_index"
    add_index :audits, :request_uuid
    add_index :audits, :created_at
  end

  def down
    drop_table :audits
  end
end
