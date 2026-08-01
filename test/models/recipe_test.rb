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

  test "accepts a bounded image cover with named card and hero variants" do
    recipe = households(:home).recipes.build(
      title: "Covered recipe",
      provenance_status: :personal,
      cover: cover_upload
    )

    assert recipe.save
    assert_predicate recipe.cover, :attached?
    assert_equal [ 640, 448 ], recipe.cover.variant(:card).variation.transformations[:resize_to_fill]
    assert_equal [ 1200, 1200 ], recipe.cover.variant(:hero).variation.transformations[:resize_to_fill]
  end

  test "rejects unsafe and oversized covers" do
    unsafe_recipe = households(:home).recipes.build(
      title: "Unsafe cover",
      provenance_status: :personal,
      cover: invalid_cover_upload
    )
    oversized_data = file_fixture("recipes/cover.png").binread
    oversized_data << "\0" * (Recipe::COVER_MAX_BYTES + 1 - oversized_data.bytesize)
    oversized_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(oversized_data),
      filename: "oversized.png",
      content_type: "image/png",
    )
    oversized_recipe = households(:home).recipes.build(
      title: "Oversized cover",
      provenance_status: :personal,
      cover: oversized_blob
    )

    assert_not unsafe_recipe.save
    assert_includes unsafe_recipe.errors[:cover], "must be a JPEG, PNG, or GIF"
    assert_not oversized_recipe.save
    assert_includes oversized_recipe.errors[:cover], "must be 10 MB or smaller"
  ensure
    oversized_blob&.purge
  end

  test "invalid replacement and invalid removal preserve the stored cover" do
    recipe = households(:home).recipes.create!(
      title: "Stable cover",
      provenance_status: :personal,
      cover: cover_upload
    )
    original_blob = recipe.cover.blob

    recipe.assign_attributes(
      title: "",
      cover: invalid_cover_upload,
      remove_cover: "1"
    )

    assert_not recipe.save
    assert_equal original_blob, recipe.reload.cover.blob

    recipe.assign_attributes(title: "", remove_cover: "1")
    assert_not recipe.save
    assert_equal original_blob, recipe.reload.cover.blob
  end

  test "successful removal purges after persistence and a replacement wins over removal" do
    recipe = households(:home).recipes.create!(
      title: "Changing cover",
      provenance_status: :personal,
      cover: cover_upload
    )
    removed_blob = recipe.cover.blob
    assert_nil recipe.cover_signed_id

    recipe.update!(remove_cover: "1")

    assert_not recipe.reload.cover.attached?
    assert_not ActiveStorage::Blob.exists?(removed_blob.id)

    recipe.cover.attach(cover_upload)
    replaced_blob = recipe.cover.blob
    recipe.assign_attributes(
      cover: replacement_cover_upload,
      cover_uploaded_this_request: true,
      remove_cover: "1"
    )
    recipe.save!

    assert_predicate recipe.reload.cover, :attached?
    assert_not_equal replaced_blob.id, recipe.cover.blob.id
    assert_not ActiveStorage::Blob.exists?(replaced_blob.id)
  end

  test "persists an uploaded blob for signed id structural form round trips" do
    recipe = households(:home).recipes.build(
      title: "Structural upload",
      provenance_status: :personal,
      cover: cover_upload
    )

    assert_difference "ActiveStorage::Blob.count", 1 do
      recipe.preserve_cover_for_form
    end

    signed_id = recipe.cover_signed_id
    assert_predicate signed_id, :present?
    assert ActiveStorage::Blob.find_signed!(signed_id).service.exist?(recipe.cover.blob.key)

    round_tripped = households(:home).recipes.build(
      title: "Structural upload",
      provenance_status: :personal,
      cover: signed_id
    )
    assert round_tripped.save
    assert_equal recipe.cover.blob, round_tripped.cover.blob
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
    ingredient = recipes(:porridge).recipe_ingredients.build(display_name: "Salt", position: 0)
    instruction = recipes(:porridge).recipe_instructions.build(body: "Serve.", position: 0)

    assert_not ingredient.valid?
    assert_not instruction.valid?
    assert_includes ingredient.errors[:position], "must be greater than 0"
    assert_includes instruction.errors[:position], "must be greater than 0"

    assert_raises(ActiveRecord::RecordNotUnique) do
      RecipeIngredient.insert!({
        recipe_id: recipes(:porridge).id,
        ingredient_id: ingredients(:rolled_oats).id,
        display_name: "Salt",
        position: 1
      })
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
    assert_equal %w[First Second], recipe.recipe_ingredients.map(&:display_name)
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

  test "ingredient lines expose exact quantities without coercing free text" do
    recipe = households(:home).recipes.create!(
      title: "Exact quantities",
      provenance_status: :personal,
      recipe_ingredients_attributes: [
        { display_name: "One", display_quantity: "2", position: 1 },
        { display_name: "Two", display_quantity: "1.25", position: 2 },
        { display_name: "Three", display_quantity: "2/3", position: 3 },
        { display_name: "Four", display_quantity: "1 1/2", position: 4 },
        { display_name: "Five", display_quantity: "to taste", position: 5 },
        { display_name: "Six", display_quantity: "1/0", position: 6 }
      ]
    )

    assert_equal [ Rational(2), Rational(5, 4), Rational(2, 3), Rational(3, 2), nil, nil ],
      recipe.recipe_ingredients.map(&:quantity)
    assert_equal [ "to taste", "1/0" ], recipe.recipe_ingredients.last(2).map(&:display_quantity)
  end

  test "ingredient lines reject canonical records from another household object" do
    recipe = households(:home).recipes.build(title: "Mismatch", provenance_status: :personal)
    line = recipe.recipe_ingredients.build(
      display_name: "Salt",
      position: 1,
      ingredient: Ingredient.new(household: Household.new, name: "Salt")
    )
    line.define_singleton_method(:resolve_ingredient) { }

    assert_not line.valid?
    assert_includes line.errors[:ingredient], "must belong to the recipe household"
  end

  test "new recipe instructions resolve multiple unsaved ingredient keys in line order" do
    recipe = households(:home).recipes.build(title: "Linked recipe", provenance_status: :personal)
    first = recipe.recipe_ingredients.build(display_name: "First", position: 1, form_key: "first-key")
    second = recipe.recipe_ingredients.build(display_name: "Second", position: 2, form_key: "second-key")
    instruction = recipe.recipe_instructions.build(
      body: "Combine.",
      position: 1,
      duration_amount: 1.5,
      duration_unit: "hours",
      temperature_amount: -5,
      temperature_unit: "C",
      ingredient_reference_keys: %w[second-key first-key]
    )

    assert recipe.save!, recipe.errors.full_messages.to_sentence
    assert_equal [ first.id, second.id ], instruction.reload.referenced_recipe_ingredients.pluck(:id)
    assert_equal [ 1, 2 ], instruction.recipe_instruction_ingredients.pluck(:position)
  end

  test "instruction cues and transient references reject incomplete duplicate and forged input" do
    recipe = households(:home).recipes.build(title: "Invalid links", provenance_status: :personal)
    recipe.recipe_ingredients.build(display_name: "First", position: 1, form_key: "first-key")
    instruction = recipe.recipe_instructions.build(
      body: "Combine.",
      position: 1,
      duration_amount: 2,
      temperature_unit: "kelvin",
      ingredient_reference_keys: %w[first-key first-key forged-key]
    )

    assert_not recipe.valid?
    assert_includes instruction.errors[:duration_unit], "must be provided with its duration"
    assert_includes instruction.errors[:temperature_unit], "is not included in the list"
    assert_includes instruction.errors[:ingredient_reference_keys], "contains duplicates"
    assert_includes instruction.errors[:ingredient_reference_keys], "contains an unknown ingredient"
  end

  test "duplicate instruction ingredient keys alone prevent persistence" do
    recipe = households(:home).recipes.build(title: "Duplicate links", provenance_status: :personal)
    recipe.recipe_ingredients.build(display_name: "First", position: 1, form_key: "first-key")
    instruction = recipe.recipe_instructions.build(
      body: "Combine.",
      position: 1,
      ingredient_reference_keys: %w[first-key first-key]
    )

    assert_no_difference "RecipeInstructionIngredient.count" do
      assert_not recipe.save
    end
    assert_includes instruction.errors[:ingredient_reference_keys], "contains duplicates"
    assert_includes recipe.errors[:base], "Step 1 referenced ingredients contain duplicates"
  end

  test "unknown instruction ingredient keys alone prevent persistence" do
    recipe = households(:home).recipes.build(title: "Forged links", provenance_status: :personal)
    recipe.recipe_ingredients.build(display_name: "First", position: 1, form_key: "first-key")
    instruction = recipe.recipe_instructions.build(
      body: "Combine.",
      position: 1,
      ingredient_reference_keys: %w[first-key forged-key]
    )

    assert_no_difference "RecipeInstructionIngredient.count" do
      assert_not recipe.save
    end
    assert_includes instruction.errors[:ingredient_reference_keys], "contains an unknown ingredient"
    assert_includes recipe.errors[:base], "Step 1 references an unknown ingredient"
  end

  test "keyed import is idempotent and reconciles reordered graphs without position collisions" do
    attributes = valid_import_attributes.merge(
      import_key: "meals:test-bowl",
      recipe_ingredients_attributes: [
        { key: "first", name: "First", amount: "1" },
        { key: "second", name: "Second", amount: "2" }
      ],
      recipe_instructions_attributes: [
        { body: "Mix.", ingredient_keys: %w[second first] },
        { body: "Serve.", ingredient_keys: [ "second" ] }
      ]
    )
    recipe = Recipe.import!(household: households(:home), attributes:)
    counts = [ Recipe.count, RecipeIngredient.count, RecipeInstruction.count, RecipeInstructionIngredient.count, Ingredient.count ]

    assert_equal recipe, Recipe.import!(household: households(:home), attributes:)
    assert_equal counts, [ Recipe.count, RecipeIngredient.count, RecipeInstruction.count, RecipeInstructionIngredient.count, Ingredient.count ]

    recipe.cover.attach(cover_upload)
    cover_blob = recipe.cover.blob
    changed = attributes.deep_merge(
      source_url: "https://example.com/moved",
      recipe_ingredients_attributes: [
        { key: "second", name: "Second", amount: "3" },
        { key: "first", name: "First", amount: "4" },
        { key: "third", name: "Third", amount: "5" }
      ],
      recipe_instructions_attributes: [
        { body: "Serve first.", ingredient_keys: %w[third first] }
      ]
    )

    assert_equal recipe, Recipe.import!(household: households(:home), attributes: changed)
    assert_equal %w[Second First Third], recipe.reload.recipe_ingredients.map(&:display_name)
    assert_equal [ 1, 2, 3 ], recipe.recipe_ingredients.pluck(:position)
    assert_equal [ "Serve first." ], recipe.recipe_instructions.pluck(:body)
    assert_equal %w[First Third], recipe.recipe_instructions.first.referenced_recipe_ingredients.pluck(:display_name)
    assert_equal [ 1, 2 ], recipe.recipe_instructions.first.recipe_instruction_ingredients.pluck(:position)
    assert_equal cover_blob, recipe.cover.blob
  end

  test "explicit import keys define identity while URLs do not" do
    first = Recipe.import!(household: households(:home), attributes: valid_import_attributes.merge(import_key: "meals:first"))
    second = Recipe.import!(household: households(:home), attributes: valid_import_attributes.merge(import_key: "meals:second"))

    assert_not_equal first, second
    assert_equal first.source_url, second.source_url

    updated = Recipe.import!(
      household: households(:home),
      attributes: valid_import_attributes.merge(import_key: "meals:first", source_url: "https://example.com/new-location")
    )
    assert_equal first, updated
  end

  test "keyed imports retry a unique insert race and converge on the existing recipe" do
    household = households(:home)
    existing = Recipe.import!(household:, attributes: valid_import_attributes.merge(import_key: "meals:race"))
    recipes = household.recipes
    original_finder = recipes.method(:find_or_initialize_by)
    attempts = 0

    finder = lambda do |attributes|
      attempts += 1
      raise ActiveRecord::RecordNotUnique if attempts == 1

      original_finder.call(attributes)
    end

    recipes.define_singleton_method(:find_or_initialize_by, finder)
    result = Recipe.import!(household:, attributes: valid_import_attributes.merge(import_key: "meals:race", title: "Race winner"))

    assert_equal existing, result
    assert_equal "Race winner", result.reload.title
    assert_equal 2, attempts
  ensure
    recipes&.singleton_class&.remove_method(:find_or_initialize_by) if recipes&.singleton_methods(false)&.include?(:find_or_initialize_by)
  end

  test "unchanged ingredient lines do not re-resolve canonical ingredients on save" do
    line = recipe_ingredients(:porridge_oats)
    ingredient_queries = []
    callback = ->(_name, _started, _finished, _unique_id, payload) {
      ingredient_queries << payload[:sql] if payload[:sql].match?(/FROM "ingredients"/)
    }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      line.update!(notes: "Freshly updated")
    end

    assert_equal "Freshly updated", line.reload.notes
    assert_operator ingredient_queries.length, :<=, 1
  end

  test "malformed keyed updates roll back the complete imported graph" do
    recipe = Recipe.import!(household: households(:home), attributes: valid_import_attributes.merge(import_key: "meals:rollback"))
    before = [ recipe.attributes, recipe.recipe_ingredients.map(&:attributes), recipe.recipe_instructions.map(&:attributes) ]

    assert_raises ActiveRecord::RecordInvalid do
      Recipe.import!(
        household: households(:home),
        attributes: valid_import_attributes.merge(import_key: "meals:rollback", title: "", recipe_ingredients_attributes: [ { name: "Changed" } ])
      )
    end

    recipe.reload
    assert_equal before, [ recipe.attributes, recipe.recipe_ingredients.map(&:attributes), recipe.recipe_instructions.map(&:attributes) ]
  end

  test "database rejects invalid quantities cues and instruction ingredient joins" do
    connection = ActiveRecord::Base.connection
    ingredient = recipe_ingredients(:porridge_oats)
    instruction = recipe_instructions(:porridge_cook)

    assert_raises(ActiveRecord::StatementInvalid) do
      connection.execute("UPDATE recipe_ingredients SET quantity_numerator = 1, quantity_denominator = 0 WHERE id = #{ingredient.id}")
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      RecipeInstruction.insert!({ recipe_id: recipes(:porridge).id, body: "Invalid", position: 99, duration_amount: 1 })
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      RecipeInstruction.insert!({ recipe_id: recipes(:porridge).id, body: "Invalid", position: 99, temperature_amount: 10, temperature_unit: "K" })
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      RecipeInstructionIngredient.insert!({
        recipe_id: recipes(:porridge).id,
        recipe_instruction_id: instruction.id,
        recipe_ingredient_id: recipe_ingredients(:salad_lettuce).id,
        position: 2
      })
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      RecipeInstructionIngredient.insert!({
        recipe_id: recipes(:porridge).id,
        recipe_instruction_id: instruction.id,
        recipe_ingredient_id: recipe_ingredients(:porridge_berries).id,
        position: 0
      })
    end
  end

  test "cannot be destroyed while a plan or meal item references it" do
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
    def cover_upload
      Rack::Test::UploadedFile.new(file_fixture("recipes/cover.png"), "image/png")
    end

    def replacement_cover_upload
      Rack::Test::UploadedFile.new(file_fixture("recipes/replacement-cover.png"), "image/png")
    end

    def invalid_cover_upload
      Rack::Test::UploadedFile.new(file_fixture("recipes/not-an-image.txt"), "text/plain")
    end

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
