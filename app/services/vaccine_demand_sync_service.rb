# Syncs vaccine demand reports from form submissions.
# Intended to run once per 24 hours (e.g. via cron + rake vaccine_demand:sync).
# The Reports page "Refresh" button calls this during development for on-demand sync.
class VaccineDemandSyncService
  def self.call
    new.sync
  end

  def sync
    State.find_each do |state|
      sync_state(state)
    end
  end

  # Sync a single state (useful for testing or partial refresh)
  def sync_state(state)
    submissions = state.form_submissions
    sums = VaccineDemandCalculator::VACCINES.index_with { |_v| zero_metrics }

    if submissions.exists?
      submissions.each do |submission|
        calc = VaccineDemandCalculator.new(submission.form_data).calculate_all
        calc.each do |vaccine, metrics|
          metrics.each do |key, value|
            sums[vaccine][key] += value
          end
        end
      end
    end

    sums.each do |vaccine, metrics|
      report = VaccineDemandReport.find_or_initialize_by(state: state, vaccine: vaccine)
      report.assign_attributes(metrics)
      report.save!
    end
  end

  private

  def zero_metrics
    {
      eligible_animals: 0.0,
      new_birth_eligible: 0.0,
      adjusted_eligible: 0.0,
      current_inventory: 0.0,
      annual_dose_requirement: 0.0,
      after_losses: 0.0,
      after_buffer: 0.0,
      monthly_demand: 0.0,
      half_yearly_demand: 0.0,
      annual_demand: 0.0
    }
  end
end
