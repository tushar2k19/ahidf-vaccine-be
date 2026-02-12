class FormSubmission < ApplicationRecord
  belongs_to :state
  belongs_to :user

  validates :form_data, presence: true
end
