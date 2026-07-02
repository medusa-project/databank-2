class CanonicalizeDatafilePeekTypeListing < ActiveRecord::Migration[8.0]
  def up
    Datafile.where(peek_type: "archive").update_all(peek_type: "listing", updated_at: Time.current)
  end

  def down
    Datafile.where(peek_type: "listing").update_all(peek_type: "archive", updated_at: Time.current)
  end
end
