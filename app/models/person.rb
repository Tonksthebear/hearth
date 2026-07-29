class Person < ApplicationRecord
  belongs_to :household
  has_one :user, dependent: :destroy
  has_many :planned_meals, dependent: :destroy
  has_many :meal_logs, dependent: :destroy
  has_many :training_sessions, dependent: :destroy

  validates :name, presence: true
  validates_associated :user
  validates :weekly_structured_minutes_target,
    :weekly_strength_sessions_target,
    :weekly_zone2_minutes_target,
    :weekly_vigorous_minutes_target,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
end
