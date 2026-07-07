# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_06_040000) do
  create_table "drawings", force: :cascade do |t|
    t.string "author", null: false
    t.datetime "created_at", null: false
    t.text "image", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.string "wall_id", null: false
    t.index ["room_id", "wall_id", "created_at"], name: "index_drawings_on_room_id_and_wall_id_and_created_at"
    t.index ["room_id"], name: "index_drawings_on_room_id"
  end

  create_table "notes", force: :cascade do |t|
    t.string "author", null: false
    t.string "board_id", null: false
    t.string "body", null: false
    t.datetime "created_at", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id", "board_id", "created_at"], name: "index_notes_on_room_id_and_board_id_and_created_at"
    t.index ["room_id"], name: "index_notes_on_room_id"
  end

  create_table "players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "heading"
    t.datetime "last_seen_at"
    t.string "name"
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.float "x"
    t.float "z"
    t.index ["room_id"], name: "index_players_on_room_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_rooms_on_slug", unique: true
  end

  create_table "soapstones", force: :cascade do |t|
    t.string "author", null: false
    t.string "body", null: false
    t.datetime "created_at", null: false
    t.string "glyph", null: false
    t.float "heading", default: 0.0, null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.float "x", null: false
    t.float "z", null: false
    t.index ["room_id", "created_at"], name: "index_soapstones_on_room_id_and_created_at"
    t.index ["room_id"], name: "index_soapstones_on_room_id"
  end

  add_foreign_key "drawings", "rooms"
  add_foreign_key "notes", "rooms"
  add_foreign_key "players", "rooms"
  add_foreign_key "soapstones", "rooms"
end
