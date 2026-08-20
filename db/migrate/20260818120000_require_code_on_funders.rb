class RequireCodeOnFunders < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE funders
      SET code = 'other'
      WHERE code IS NULL OR code = ''
    SQL

    change_column_default :funders, :code, from: nil, to: "other"
    change_column_null :funders, :code, false
  end

  def down
    change_column_null :funders, :code, true
    change_column_default :funders, :code, from: "other", to: nil
  end
end