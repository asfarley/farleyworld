class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.string :name
      t.references :room, null: false, foreign_key: true
      t.float :x
      t.float :z
      t.float :heading
      t.datetime :last_seen_at

      t.timestamps
    end
  end
end
