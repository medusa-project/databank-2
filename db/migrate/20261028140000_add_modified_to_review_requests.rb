class AddModifiedToReviewRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :review_requests, :modified, :boolean, default: false, null: false

    # Existing requests have no content snapshot, so their freshness cannot be verified.
    execute "UPDATE review_requests SET modified = TRUE"
  end

  def down
    remove_column :review_requests, :modified
  end
end
