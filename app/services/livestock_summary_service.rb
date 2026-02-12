# Aggregates livestock population from form_submissions per state.
# Used by the Livestock Summary view so users can see cattle/buffalo/sheep+goat/pig per state
# and verify figures used in Reports (vaccine demand).
class LivestockSummaryService
  POPULATION_KEYS = {
    cattle: 'population_cattle',
    buffalo: 'population_buffalo',
    sheep_goat: 'population_sheep_goat',
    pig: 'population_pig'
  }.freeze

  ALIASES = {
    'population_cattle' => ['population of cattle'],
    'population_buffalo' => ['population of Buffalo'],
    'population_sheep_goat' => ['population of Sheep + Goat'],
    'population_pig' => ['population of Pig']
  }.freeze

  def self.call(state_id: nil)
    new(state_id: state_id).call
  end

  def initialize(state_id: nil)
    @state_id = state_id
  end

  def call
    states = @state_id ? State.where(id: @state_id) : State.order(:name)
    states.map { |state| summary_for_state(state) }
  end

  private

  def summary_for_state(state)
    submissions = state.form_submissions
    cattle = buffalo = sheep_goat = pig = 0.0

    submissions.each do |sub|
      data = (sub.form_data || {}).stringify_keys
      cattle += get_float(data, 'population_cattle')
      buffalo += get_float(data, 'population_buffalo')
      sheep_goat += get_float(data, 'population_sheep_goat')
      pig += get_float(data, 'population_pig')
    end

    total = cattle + buffalo + sheep_goat + pig
    {
      state_id: state.id,
      state_name: state.name,
      cattle: cattle.round(2),
      buffalo: buffalo.round(2),
      sheep_goat: sheep_goat.round(2),
      pig: pig.round(2),
      total_eligible_animals: total.round(2)
    }
  end

  def get_float(data, key)
    val = data[key].presence || data[key.to_sym].presence
    unless val.present?
      ALIASES[key]&.each do |alt|
        val = data[alt].presence || data[alt.to_sym].presence
        break if val.present?
      end
    end
    (val || 0).to_f
  end
end
