class AddFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :token_digest, :string

    add_index :users, :name, unique: true
    add_index :users, :api_token, unique: true
    add_index :users, :token_digest, unique: true

    change_column_null :users, :name, false
    change_column_default :users, :active, true
  end
end
