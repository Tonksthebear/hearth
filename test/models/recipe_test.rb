require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  test "requires catalog identity and an exact provenance status" do
    recipe = households(:home).recipes.build

    assert_not recipe.valid?
    assert_includes recipe.errors[:title], "can't be blank"
    assert_includes recipe.errors[:source_name], "can't be blank"
    assert_includes recipe.errors[:provenance_status], "is not included in the list"

    assert_equal %w[personal verified adapted observed], Recipe.provenance_statuses.keys
  end

  test "personal recipes persist without a source" do
    recipe = households(:home).recipes.create!(
      title: "Household pasta",
      provenance_status: :personal
    )

    assert_nil recipe.source_name
    assert_equal "From your household", recipe.source_label
  end

  test "imported provenance statuses still require a source" do
    %i[verified adapted observed].each do |status|
      recipe = households(:home).recipes.build(title: status.to_s, provenance_status: status)

      assert_not recipe.valid?
      assert_includes recipe.errors[:source_name], "can't be blank"
    end
  end

  test "database rejects unsupported provenance inserted below validations" do
    assert_raises ActiveRecord::StatementInvalid do
      Recipe.insert!({
        household_id: households(:home).id,
        title: "Unsupported",
        provenance_status: "unsupported",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "orders nested records and destroys them with the recipe" do
    recipe = recipes(:porridge)

    assert_equal [ 1, 2 ], recipe.recipe_ingredients.map(&:position)
    assert_equal [ 1, 2 ], recipe.recipe_instructions.map(&:position)

    assert_difference({
      "Recipe.count" => -1,
      "RecipeIngredient.count" => -2,
      "RecipeInstruction.count" => -2
    }) do
      recipe.destroy!
    end
  end

  test "child positions are positive and protected by unique database indexes" do
    ingredient = recipes(:porridge).recipe_ingredients.build(name: "Salt", position: 0)
    instruction = recipes(:porridge).recipe_instructions.build(body: "Serve.", position: 0)

    assert_not ingredient.valid?
    assert_not instruction.valid?
    assert_includes ingredient.errors[:position], "must be greater than 0"
    assert_includes instruction.errors[:position], "must be greater than 0"

    assert_raises(ActiveRecord::RecordNotUnique) do
      RecipeIngredient.insert!({ recipe_id: recipes(:porridge).id, name: "Salt", position: 1 })
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      RecipeInstruction.insert!({ recipe_id: recipes(:porridge).id, body: "Serve.", position: 1 })
    end
  end

  test "rejects entirely blank nested rows" do
    recipe = households(:home).recipes.build(
      title: "Blank rows",
      source_name: "Test",
      provenance_status: :observed,
      recipe_ingredients_attributes: [ {} ],
      recipe_instructions_attributes: [ {} ]
    )

    assert_empty recipe.recipe_ingredients
    assert_empty recipe.recipe_instructions
  end

  test "searches recipe and ingredient text without duplicates" do
    assert_equal [ recipes(:porridge) ], Recipe.matching("morning").to_a
    assert_equal [ recipes(:porridge) ], Recipe.matching("blueberries").to_a
    assert_equal [ recipes(:porridge) ], Recipe.matching("hearth test").to_a
    refute_includes Recipe.matching("lettuce"), recipes(:porridge)
  end

  test "escapes wildcard input and composes with provenance" do
    literal = households(:home).recipes.create!(
      title: "100% Bowl",
      source_name: "Test",
      provenance_status: :verified
    )

    assert_equal [ literal ], Recipe.matching("100%").to_a
    assert_empty Recipe.matching("100_")
    assert_includes Recipe.matching("salad").with_provenance_status("adapted"), recipes(:salad)
    refute_includes Recipe.matching("salad").with_provenance_status("verified"), recipes(:salad)
  end

  test "imports a complete ordered graph" do
    recipe = nil

    assert_difference({
      "Recipe.count" => 1,
      "RecipeIngredient.count" => 2,
      "RecipeInstruction.count" => 2
    }) do
      recipe = Recipe.import!(household: households(:home), attributes: valid_import_attributes)
    end

    assert_equal "Imported Bowl", recipe.title
    assert_equal %w[First Second], recipe.recipe_ingredients.map(&:name)
    assert_equal [ 1, 2 ], recipe.recipe_ingredients.map(&:position)
    assert_equal [ "Mix.", "Serve." ], recipe.recipe_instructions.map(&:body)
    assert_equal [ 1, 2 ], recipe.recipe_instructions.map(&:position)
  end

  test "rejects malformed imports atomically" do
    malformed_payloads = [
      nil,
      valid_import_attributes.merge(unexpected: true),
      valid_import_attributes.merge(recipe_ingredients_attributes: "not an array"),
      valid_import_attributes.merge(recipe_instructions_attributes: [ "not a hash" ]),
      valid_import_attributes.deep_merge(recipe_ingredients_attributes: [ { name: "First", position: 8 } ])
    ]

    malformed_payloads.each do |payload|
      assert_no_difference [ "Recipe.count", "RecipeIngredient.count", "RecipeInstruction.count" ] do
        error = assert_raises(ArgumentError) do
          Recipe.import!(household: households(:home), attributes: payload)
        end
        assert_predicate error.message, :present?
      end
    end
  end

  test "raises record invalid for semantic import failures without partial writes" do
    attributes = valid_import_attributes.deep_merge(
      title: "",
      recipe_ingredients_attributes: [ { name: "" } ]
    )

    assert_no_difference [ "Recipe.count", "RecipeIngredient.count", "RecipeInstruction.count" ] do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Recipe.import!(household: households(:home), attributes: attributes)
      end
      assert_predicate error.record.errors, :any?
    end
  end

  test "cannot be destroyed while a plan or meal log references it" do
    planned_recipe = recipes(:salad)
    logged_recipe = recipes(:observed_soup)

    assert_raises ActiveRecord::DeleteRestrictionError do
      planned_recipe.destroy!
    end
    assert_raises ActiveRecord::DeleteRestrictionError do
      logged_recipe.destroy!
    end
  end

  private
    def valid_import_attributes
      {
        title: "Imported Bowl",
        description: "Normalized catalog data",
        yield: "2 bowls",
        source_name: "Imported source",
        source_url: "https://example.com/imported",
        provenance_status: "adapted",
        recipe_ingredients_attributes: [
          { name: "First", amount: "1" },
          { name: "Second", amount: "2" }
        ],
        recipe_instructions_attributes: [
          { body: "Mix." },
          { body: "Serve." }
        ]
      }
    end
end
