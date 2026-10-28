require "rails_helper"

RSpec.describe Dataset::Reviewable do
  let(:dataset) { create(:dataset) }

  def create_review_request(dataset)
    dataset.review_requests.create!(
      requester_name: "Review Requester",
      requester_email: "requester@example.edu",
      requested_at: Time.current
    )
  end

  it "treats a new latest review request as unmodified" do
    create_review_request(dataset)

    expect(dataset).to have_unmodified_review
  end

  it "marks a review request modified when dataset metadata changes" do
    review_request = create_review_request(dataset)

    dataset.update!(title: "Updated title")

    expect(review_request.reload).to be_modified
    expect(dataset).not_to have_unmodified_review
  end

  it "marks a review request modified when a creator changes" do
    creator = create(:creator, dataset: dataset)
    review_request = create_review_request(dataset)

    creator.update!(email: "updated@example.edu")

    expect(review_request.reload).to be_modified
  end

  it "marks a review request modified when a file is added" do
    review_request = create_review_request(dataset)

    create(:datafile, dataset: dataset)

    expect(review_request.reload).to be_modified
  end

  it "treats a later request as unmodified after an older request was modified" do
    old_request = create_review_request(dataset)
    dataset.update!(title: "Updated title")
    new_request = create_review_request(dataset)

    expect(old_request.reload).to be_modified
    expect(new_request).not_to be_modified
    expect(dataset).to have_unmodified_review
  end
end
