class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.references :room, null: false, foreign_key: true
      t.string :board_id, null: false
      t.string :author, null: false
      t.string :body, null: false
      t.timestamps
    end
    add_index :notes, [ :room_id, :board_id, :created_at ]
  end
end
