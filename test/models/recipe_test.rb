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
