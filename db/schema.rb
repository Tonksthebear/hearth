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

ActiveRecord::Schema[8.1].define(version: 2026_07_28_220002) do
  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "installation_key", default: 1, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_key"], name: "index_households_on_installation_key", unique: true
    t.check_constraint "installation_key = 1", name: "households_single_installation"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_people_on_household_id"
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.text "amount"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "position", null: false
    t.integer "recipe_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["recipe_id", "position"], name: "index_recipe_ingredients_on_recipe_id_and_position", unique: true
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
    t.check_constraint "position > 0", name: "recipe_ingredients_positive_position"
  end

  create_table "recipe_instructions", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id", "position"], name: "index_recipe_instructions_on_recipe_id_and_position", unique: true
    t.index ["recipe_id"], name: "index_recipe_instructions_on_recipe_id"
    t.check_constraint "position > 0", name: "recipe_instructions_positive_position"
  end

  create_table "recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "provenance_status", null: false
    t.string "source_name", null: false
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "yield"
    t.index ["household_id", "provenance_status"], name: "index_recipes_on_household_id_and_provenance_status"
    t.index ["household_id"], name: "index_recipes_on_household_id"
    t.check_constraint "provenance_status IN ('verified', 'adapted', 'observed')", name: "recipes_provenance_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["person_id"], name: "index_users_on_person_id", unique: true
  end

  add_foreign_key "people", "households"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_instructions", "recipes"
  add_foreign_key "recipes", "households"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "people"
end
