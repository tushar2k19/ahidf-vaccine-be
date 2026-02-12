class StatesController < ApplicationController
  before_action :authorize_access_request!

  # GET /states
  def index
    states = State.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    render_success(states)
  end
end
