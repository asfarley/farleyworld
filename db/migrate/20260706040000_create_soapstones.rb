class CreateSoapstones < ActiveRecord::Migration[8.1]
  def change
    create_table :soapstones do |t|
      t.references :room, null: false, foreign_key: true
      t.float :x, null: false
      t.float :z, null: false
      t.float :heading, null: false, default: 0.0
      t.string :glyph, null: false
      t.string :body, null: false
      t.string :author, null: false
      t.timestamps
    end
    add_index :soapstones, [ :room_id, :created_at ]
  end
end
