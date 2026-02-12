class LivestockSummariesController < ApplicationController
  before_action :authorize_access_request!

  # GET /livestock_summaries
  # Optional: ?state_id=1 to filter by state
  def index
    state_id = params[:state_id].presence
    data = LivestockSummaryService.call(state_id: state_id)
    render json: data
  end
end
