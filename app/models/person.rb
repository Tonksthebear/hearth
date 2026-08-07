class Person < ApplicationRecord
  belongs_to :household
  has_one :user, dependent: :destroy
  has_many :planned_meals, dependent: :destroy
  has_many :meals, dependent: :destroy
  has_many :training_sessions, dependent: :destroy
  has_many :planned_workouts, dependent: :destroy
  has_many :person_habits, dependent: :destroy
  has_many :habit_check_ins, through: :person_habits
  has_many :agent_conversations, class_name: "Agent::Conversation", dependent: :restrict_with_exception
  has_many :confirmed_pantry_items,
    class_name: "PantryItem",
    foreign_key: :confirmed_by_id,
    dependent: :restrict_with_exception,
    inverse_of: :confirmed_by

  accepts_nested_attributes_for :user, update_only: true, reject_if: ->(attributes) { attributes["email_address"].blank? }

  validates :name, presence: true
  validates :weekly_structured_minutes_target,
    :weekly_strength_sessions_target,
    :weekly_zone2_minutes_target,
    :weekly_vigorous_minutes_target,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
end
