class Person < ApplicationRecord
  belongs_to :household
  has_one :user, dependent: :destroy
  has_many :planned_meals, dependent: :destroy
  has_many :meal_logs, dependent: :destroy

  validates :name, presence: true
  validates_associated :user
end
