class AllowPersonalRecipeProvenance < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :recipes,
      "provenance_status IN ('verified', 'adapted', 'observed')",
      name: "recipes_provenance_status"
    add_check_constraint :recipes,
      "provenance_status IN ('personal', 'verified', 'adapted', 'observed')",
      name: "recipes_provenance_status"
    change_column_null :recipes, :source_name, true
  end
end
