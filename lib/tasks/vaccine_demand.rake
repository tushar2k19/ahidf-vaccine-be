# Rake tasks for vaccine demand batch sync.
# In production, run once per 24 hours (e.g. cron at 2 AM):
#   0 2 * * * cd /path/to/backend && bundle exec rails vaccine_demand:sync
namespace :vaccine_demand do
  desc 'Sync vaccine demand reports from form submissions (run daily, e.g. via cron)'
  task sync: :environment do
    puts "[#{Time.current}] Starting vaccine demand sync..."
    VaccineDemandSyncService.call
    puts "[#{Time.current}] Vaccine demand sync completed."
  end
end
