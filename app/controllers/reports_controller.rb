class ReportsController < ApplicationController
  before_action :authorize_access_request!

  def index
    reports = VaccineDemandReport.includes(:state).all

    if params[:state_id].present?
      reports = reports.where(state_id: params[:state_id])
    end

    render json: reports.as_json(include: { state: { only: [:id, :name] } })
  end

  # On-demand sync (temporary for development). Production uses daily batch via rake vaccine_demand:sync.
  def refresh
    VaccineDemandSyncService.call
    render json: { message: 'Reports refreshed successfully' }
  end
end
