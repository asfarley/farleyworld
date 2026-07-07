class CreateDrawings < ActiveRecord::Migration[8.1]
  def change
    create_table :drawings do |t|
      t.references :room, null: false, foreign_key: true
      t.string :wall_id, null: false
      t.string :author, null: false
      t.text :image, null: false   # transparent PNG as a data: URL
      t.timestamps
    end
    add_index :drawings, [ :room_id, :wall_id, :created_at ]
  end
end
