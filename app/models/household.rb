class Household < ApplicationRecord
  has_many :people, dependent: :destroy
  has_many :users, through: :people
  has_many :planned_meals, dependent: :destroy
  has_many :meal_logs, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :training_sessions, dependent: :destroy
  has_many :planned_workouts, dependent: :destroy
  has_many :workout_templates, dependent: :destroy
  has_many :exercises, dependent: :destroy
  has_many :habits, dependent: :destroy
  has_many :agent_profiles, class_name: "Agent::Profile", dependent: :restrict_with_exception
  has_many :agent_conversations, class_name: "Agent::Conversation", dependent: :restrict_with_exception

  validates :name, presence: true
  validates :installation_key, inclusion: { in: [ 1 ] }, uniqueness: true

  def person_for(person_id, fallback:)
    people.find_by(id: person_id) || fallback
  end

  def setup_error_messages
    [
      *setup_errors_for(self, except: :people),
      *setup_errors_for(people.first, except: :user),
      *setup_errors_for(people.first&.user)
    ].uniq
  end

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

  private
    def setup_errors_for(record, except: nil)
      return [] unless record

      record.errors.reject { |error| error.attribute == except }.map(&:full_message)
    end
end
