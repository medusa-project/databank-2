class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.guest

    if user.curator?
      can :manage, :all
      return
    end

    can :read, Dataset, &:publicly_readable_now?
    can :view_files, Dataset, &:files_publicly_readable_now?
    can :create, Dataset if user.depositor?

    can %i[read update destroy publish], Dataset do |dataset|
      dataset.depositor_email == user.email
    end

    can :view_files, Dataset do |dataset|
      dataset.depositor_email == user.email
    end

    can :manage_access, Dataset do |dataset|
      dataset.depositor_email == user.email
    end

    # Creators have read and edit access to their datasets
    can :read, Dataset do |dataset|
      user.email.present? && Creator.exists?(dataset_id: dataset.id, email: user.email.downcase)
    end

    can :view_files, Dataset do |dataset|
      user.email.present? && Creator.exists?(dataset_id: dataset.id, email: user.email.downcase)
    end

    can :update, Dataset do |dataset|
      user.email.present? && Creator.exists?(dataset_id: dataset.id, email: user.email.downcase)
    end

    can :read, Dataset do |dataset|
      user.email.present? && DatasetAccessGrant.grants_read_access?(dataset_id: dataset.id, email: user.email)
    end

    can :view_files, Dataset do |dataset|
      user.email.present? && DatasetAccessGrant.grants_read_access?(dataset_id: dataset.id, email: user.email)
    end

    can :update, Dataset do |dataset|
      user.email.present? && DatasetAccessGrant.grants_edit_access?(dataset_id: dataset.id, email: user.email)
    end
  end
end
