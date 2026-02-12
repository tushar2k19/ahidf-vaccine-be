class FormSubmissionsController < ApplicationController
  before_action :authorize_access_request!

  # POST /form_submissions
  def create
    submission = current_user.form_submissions.build(form_submission_params)

    if submission.save
      render_success(
        { id: submission.id, state_id: submission.state_id, created_at: submission.created_at.iso8601 },
        message: 'Form submitted successfully',
        status: :created
      )
    else
      render_error(
        'VALIDATION_ERROR',
        submission.errors.full_messages.join(', '),
        details: submission.errors.messages,
        status: :unprocessable_entity
      )
    end
  end

  private

  def form_submission_params
    params.require(:form_submission).permit(:state_id, form_data: {})
  end
end
