class CreateVaccineDemandReports < ActiveRecord::Migration[7.1]
  def change
    create_table :vaccine_demand_reports do |t|
      t.references :state, null: false, foreign_key: true
      t.string :vaccine, null: false
      t.decimal :eligible_animals, precision: 15, scale: 2
      t.decimal :new_birth_eligible, precision: 15, scale: 2
      t.decimal :adjusted_eligible, precision: 15, scale: 2
      t.decimal :current_inventory, precision: 15, scale: 2
      t.decimal :annual_dose_requirement, precision: 15, scale: 2
      t.decimal :after_losses, precision: 15, scale: 2
      t.decimal :after_buffer, precision: 15, scale: 2
      t.decimal :monthly_demand, precision: 15, scale: 2
      t.decimal :half_yearly_demand, precision: 15, scale: 2
      t.decimal :annual_demand, precision: 15, scale: 2

      t.timestamps
    end
    add_index :vaccine_demand_reports, [:state_id, :vaccine], unique: true
  end
end
