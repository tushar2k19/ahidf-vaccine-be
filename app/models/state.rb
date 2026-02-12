class State < ApplicationRecord
  has_many :form_submissions, dependent: :restrict_with_error
  has_many :vaccine_demand_reports, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
