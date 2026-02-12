class VaccineDemandCalculator
  VACCINES = ['FMD', 'Brucellosis', 'PPR', 'CSF', 'LSD'].freeze

  # Default Assumptions
  DEFAULT_CALVING_RATE = 0.55
  DEFAULT_FEMALE_CALF_PCT = 0.45
  DEFAULT_COVERAGE_PCT = 0.95
  DEFAULT_WASTAGE_PCT = 0.10
  DEFAULT_BUFFER_PCT = 0.15
  BRUCELLOSIS_FEMALE_PCT = 0.45

  # Map snake_case keys (from current frontend) to long form keys (from docs/imports)
  KEY_ALIASES = {
    'population_cattle' => ['population of cattle'],
    'population_buffalo' => ['population of Buffalo'],
    'population_sheep_goat' => ['population of Sheep + Goat'],
    'population_pig' => ['population of Pig'],
    'estimated_annual_new_birth' => ['Estimated Annual New Birth (all species combined)'],
    'coverage_percent' => ['coverage % (target of vaccine coverage)'],
    'wastage_percent' => ['Wastage % (wastage during operation and in-transit)'],
    'buffer_percent' => ['Buffer % ', 'Buffer %'],
    'stock_fmd' => ['Existing Vaccine Stock - FMD'],
    'stock_brucellosis' => ['Existing Vaccine Stock - Brucellosis'],
    'stock_ppr' => ['Existing Vaccine Stock - PPR'],
    'stock_csf' => ['Existing Vaccine Stock - CSF'],
    'stock_lsd' => ['Existing Vaccine Stock - LSD']
  }.freeze

  def initialize(form_data)
    @data = form_data || {}
    # Ensure string keys for consistency if symbols passed
    @data = @data.stringify_keys if @data.respond_to?(:stringify_keys)
  end

  def calculate_all
    VACCINES.index_with { |vaccine| calculate_for_vaccine(vaccine) }
  end

  private

  # Try primary key (snake_case) then any aliases (long form) so both form_data formats work
  def get_float(key, default = 0.0)
    val = @data[key].presence
    unless val.present?
      KEY_ALIASES[key]&.each do |alt|
        val = @data[alt].presence
        break if val.present?
      end
    end
    (val || default).to_f
  end

  def get_value(key)
    val = @data[key].presence
    unless val.present?
      KEY_ALIASES[key]&.each do |alt|
        val = @data[alt].presence
        break if val.present?
      end
    end
    val
  end

  def calculate_for_vaccine(vaccine)
    # b. Eligible Animals
    eligible_animals = calculate_eligible_animals(vaccine)

    # c. New Birth Eligible
    # Formula: Eligible Animals × Calving Rate × Female Calf % = 0.2475 × Eligible Animals (per vaccine).
    # Must be computed per vaccine from that vaccine's Eligible Animals, not from form "all species" value.
    new_birth_eligible = eligible_animals * DEFAULT_CALVING_RATE * DEFAULT_FEMALE_CALF_PCT

    # d. Adjusted Eligible (Coverage)
    # Coverage % from form (frontend sends 0-100; or long-form key)
    coverage_input = get_value('coverage_percent')
    coverage_pct = coverage_input.present? ? (coverage_input.to_f / 100.0) : DEFAULT_COVERAGE_PCT
    adjusted_eligible = coverage_pct * (eligible_animals + new_birth_eligible)

    # e. Current Inventory
    current_inventory = get_float("stock_#{vaccine.downcase}")

    # f. Annual Dose Requirement
    doses_per_year = case vaccine
                     when 'FMD' then 2
                     else 1
                     end
    annual_dose_requirement = doses_per_year * adjusted_eligible

    # g. After Losses
    wastage_input = get_value('wastage_percent')
    wastage_pct = wastage_input.present? ? (wastage_input.to_f / 100.0) : DEFAULT_WASTAGE_PCT
    after_losses = (1 + wastage_pct) * annual_dose_requirement

    # h. After Buffer & Campaign
    buffer_input = get_value('buffer_percent')
    buffer_pct = buffer_input.present? ? (buffer_input.to_f / 100.0) : DEFAULT_BUFFER_PCT
    after_buffer = (1 + buffer_pct) * after_losses

    # i, j, k Demand
    annual_demand = after_buffer
    monthly_demand = annual_demand / 12.0
    half_yearly_demand = annual_demand / 2.0

    {
      eligible_animals: eligible_animals,
      new_birth_eligible: new_birth_eligible,
      adjusted_eligible: adjusted_eligible,
      current_inventory: current_inventory,
      annual_dose_requirement: annual_dose_requirement,
      after_losses: after_losses,
      after_buffer: after_buffer,
      monthly_demand: monthly_demand,
      half_yearly_demand: half_yearly_demand,
      annual_demand: annual_demand
    }
  end

  def calculate_eligible_animals(vaccine)
    cattle = get_float('population_cattle')
    buffalo = get_float('population_buffalo')
    sheep_goat = get_float('population_sheep_goat')
    pig = get_float('population_pig')

    case vaccine
    when 'FMD'
      cattle + buffalo + sheep_goat + pig
    when 'Brucellosis'
      BRUCELLOSIS_FEMALE_PCT * (cattle + buffalo)
    when 'PPR'
      sheep_goat
    when 'CSF'
      pig
    when 'LSD'
      cattle
    else
      0.0
    end
  end
end
