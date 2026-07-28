class Household < ApplicationRecord
  has_many :people, dependent: :destroy
  has_many :users, through: :people

  validates :name, presence: true
  validates :installation_key, inclusion: { in: [ 1 ] }, uniqueness: true

  class << self
    def configured?
      exists?
    end

    def bootstrap(household_attributes:, person_attributes:, user_attributes:)
      household = new(household_attributes)
      person = household.people.build(person_attributes)
      person.build_user(user_attributes)
      household.save
      household
    rescue ActiveRecord::RecordNotUnique
      household.errors.add(:base, "Household setup is no longer available.")
      household
    end
  end
end
