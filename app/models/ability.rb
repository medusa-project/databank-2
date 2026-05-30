class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.guest

    if user.admin?
      can :manage, :all
      return
    end

    can :read, Dataset, &:publicly_readable_now?
    can :create, Dataset if user.depositor?

    can %i[read update destroy publish], Dataset do |dataset|
      dataset.depositor_email == user.email
    end
  end
end
