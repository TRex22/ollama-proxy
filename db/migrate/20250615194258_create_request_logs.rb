class CreateRequestLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :request_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :http_method
      t.string :path
      t.string :ollama_model
      t.string :server_used
      t.integer :response_status
      t.decimal :response_time_ms
      t.text :error_message

      t.timestamps
    end
  end
end
