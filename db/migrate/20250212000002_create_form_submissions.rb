class CreateFormSubmissions < ActiveRecord::Migration[7.1]
  def change
    create_table :form_submissions do |t|
      t.references :state, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.json :form_data, null: false

      t.timestamps
    end
  end
end
