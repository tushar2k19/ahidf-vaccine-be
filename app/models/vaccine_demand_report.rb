class VaccineDemandReport < ApplicationRecord
  belongs_to :state

  validates :vaccine, presence: true, uniqueness: { scope: :state_id }
end
