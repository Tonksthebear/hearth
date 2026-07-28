class Person < ApplicationRecord
  belongs_to :household
  has_one :user, dependent: :destroy

  validates :name, presence: true
  validates_associated :user
end
