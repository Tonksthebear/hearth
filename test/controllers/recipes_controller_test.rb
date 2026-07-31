require "test_helper"

class RecipesControllerTest < ActionDispatch::IntegrationTest
  test "anonymous requests require authentication" do
    get recipes_path
    assert_redirected_to new_session_path

    get new_recipe_path
    assert_redirected_to new_session_path

    post recipes_path, params: { recipe: valid_recipe_params }
    assert_redirected_to new_session_path
  end

  test "lists searches and filters the household catalog" do
    sign_in_as users(:one)

    get recipes_path
    assert_response :success
    assert_select "h2", text: recipes(:porridge).title
    assert_select "h2", text: recipes(:salad).title

    get recipes_path, params: { q: "blueberries" }
    assert_response :success
    assert_select "h2", text: recipes(:porridge).title
    assert_select "h2", text: recipes(:salad).title, count: 0

    get recipes_path, params: { status: "adapted" }
    assert_response :success
    assert_select "h2", text: recipes(:salad).title
    assert_select "h2", text: recipes(:porridge).title, count: 0
  end

  test "index leads with recipe cards and show leads with cooking content" do
    sign_in_as users(:one)

    get recipes_path

    assert_response :success
    cards_position = response.body.index(%(role="list"))
    source_details_position = response.body.index("Source details")
    assert_operator cards_position, :<, source_details_position
    %w[Personal Verified Adapted Observed].each do |label|
      assert_operator response.body.index(label), :>, cards_position
    end

    get recipe_path(recipes(:porridge))

    assert_response :success
    ingredients_position = response.body.index("Ingredients")
    instructions_position = response.body.index("Instructions")
    source_details_position = response.body.index("Source details")
    assert_operator ingredients_position, :<, source_details_position
    assert_operator instructions_position, :<, source_details_position
    assert_select "nav[aria-label='Breadcrumb']", text: /Recipes.*#{Regexp.escape(recipes(:porridge).title)}/
    assert_select "p", text: "Household recipe", count: 0
  end

  test "shows attribution provenance and medical information disclaimer" do
    sign_in_as users(:one)

    get recipe_path(recipes(:porridge))

    assert_response :success
    assert_select "h1", text: recipes(:porridge).title
    assert_select "dd", text: /#{Regexp.escape(recipes(:porridge).source_name)}/
    assert_select "dd", text: /#{Regexp.escape(recipes(:porridge).source_url)}/
    assert_select "p", text: /not clinical endorsement/i
    assert_select "p", text: /does not provide medical advice/i
  end

  test "index explains every available provenance status as secondary details" do
    sign_in_as users(:one)

    get recipes_path

    assert_response :success
    Recipe.provenance_statuses.each_key do |status|
      assert_select "dt", text: "#{status.humanize}:"
      assert_select "dd", text: Recipe::PROVENANCE_DESCRIPTIONS.fetch(status)
    end
    assert_select ".bg-primary-50", text: /About provenance/, count: 0
  end

  test "person context does not change the shared catalog" do
    sign_in_as users(:one)

    patch person_context_path, params: { person_id: people(:two).id }
    assert_redirected_to root_path

    get recipes_path

    assert_response :success
    assert_select "h2", text: recipes(:porridge).title
    assert_select "[aria-current='true']", text: people(:two).name
  end

  test "creates and updates a recipe through the household association" do
    sign_in_as users(:one)
    recipe = nil

    assert_difference [ "Recipe.count", "RecipeIngredient.count", "RecipeInstruction.count" ], 1 do
      post recipes_path, params: { recipe: valid_recipe_params }
    end

    recipe = households(:home).recipes.find_by!(title: "Savory Bowl")
    assert_redirected_to recipe_path(recipe)
    assert_response :see_other
    assert_equal [ 1 ], recipe.recipe_ingredients.pluck(:position)
    assert_equal [ 1 ], recipe.recipe_instructions.pluck(:position)

    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(title: "Updated Savory Bowl")
    }

    assert_redirected_to recipe_path(recipe)
    assert_response :see_other
    assert_equal "Updated Savory Bowl", recipe.reload.title
  end

  test "creates displays replaces and removes a cover" do
    sign_in_as users(:one)

    post recipes_path, params: {
      recipe: valid_recipe_params.merge(
        cover: fixture_file_upload("recipes/cover.png", "image/png")
      )
    }

    recipe = households(:home).recipes.find_by!(title: "Savory Bowl")
    assert_redirected_to recipe_path(recipe)
    assert_predicate recipe.cover, :attached?

    get recipes_path
    assert_response :success
    assert_select "a[href='#{recipe_path(recipe)}'] img[alt='']"

    get recipe_path(recipe)
    assert_response :success
    assert_select "img[alt='Savory Bowl cover'][src*='/rails/active_storage/representations/']"

    original_blob = recipe.cover.blob
    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        cover: fixture_file_upload("recipes/replacement-cover.png", "image/png"),
        remove_cover: "1"
      )
    }

    assert_response :see_other
    assert_not_equal original_blob.id, recipe.reload.cover.blob.id
    assert_not ActiveStorage::Blob.exists?(original_blob.id)

    current_blob = recipe.cover.blob
    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(remove_cover: "1")
    }

    assert_response :see_other
    assert_not recipe.reload.cover.attached?
    assert_not ActiveStorage::Blob.exists?(current_blob.id)
  end

  test "invalid cover create and replacement fail without losing stored data" do
    sign_in_as users(:one)

    assert_no_difference "Recipe.count" do
      post recipes_path, params: {
        recipe: valid_recipe_params.merge(
          cover: fixture_file_upload("recipes/not-an-image.txt", "text/plain")
        )
      }
    end
    assert_response :unprocessable_entity
    assert_select "#recipe-errors", text: /Cover must be a JPEG, PNG, or GIF/

    recipe = recipes(:porridge)
    recipe.cover.attach(fixture_file_upload("recipes/cover.png", "image/png"))
    original_blob = recipe.cover.blob

    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        cover: fixture_file_upload("recipes/not-an-image.txt", "text/plain")
      )
    }

    assert_response :unprocessable_entity
    assert_select "#recipe-errors", text: /Cover must be a JPEG, PNG, or GIF/
    assert_equal original_blob, recipe.reload.cover.blob
    assert_select "img[alt='#{recipe.title} cover']"
    assert_select "label", text: "Remove cover when this recipe is saved"
  end

  test "malformed cover references render errors without changing stored data" do
    sign_in_as users(:one)

    assert_no_difference [ "Recipe.count", "ActiveStorage::Blob.count" ] do
      post recipes_path, params: {
        recipe: valid_recipe_params.merge(cover: "not-a-signed-id")
      }
    end

    assert_response :unprocessable_entity
    assert_select "#recipe-errors", text: /Cover is invalid/

    recipe = recipes(:porridge)
    recipe.cover.attach(fixture_file_upload("recipes/cover.png", "image/png"))
    original_title = recipe.title
    original_blob = recipe.cover.blob

    assert_no_difference "ActiveStorage::Blob.count" do
      patch recipe_path(recipe), params: {
        recipe: persisted_recipe_params(recipe).merge(
          title: "Must not persist",
          cover: "not-a-signed-id"
        )
      }
    end

    assert_response :unprocessable_entity
    assert_select "#recipe-errors", text: /Cover is invalid/
    assert_select "img[alt='Must not persist cover']"
    assert_equal original_title, recipe.reload.title
    assert_equal original_blob, recipe.cover.blob
  end

  test "invalid create and update render their forms" do
    sign_in_as users(:one)

    assert_no_difference "Recipe.count" do
      post recipes_path, params: { recipe: valid_recipe_params.merge(title: "") }
    end
    assert_response :unprocessable_entity
    assert_select "#recipe-errors", text: /Title can't be blank/

    recipe = recipes(:porridge)
    patch recipe_path(recipe), params: {
      recipe: valid_recipe_params.merge(title: "", recipe_ingredients_attributes: {})
    }
    assert_response :unprocessable_entity
    assert_select "#recipe-errors", text: /Title can't be blank/
    assert_equal recipes(:porridge).title, recipe.reload.title
  end

  test "valid covers survive create and update validation errors" do
    sign_in_as users(:one)

    assert_no_difference "Recipe.count" do
      post recipes_path, params: {
        recipe: valid_recipe_params.merge(
          title: "",
          cover: fixture_file_upload("recipes/cover.png", "image/png")
        )
      }
    end

    assert_response :unprocessable_entity
    create_signed_id = css_select("input[type='hidden'][name='recipe[cover]']").sole["value"]
    create_blob = ActiveStorage::Blob.find_signed!(create_signed_id)
    assert create_blob.service.exist?(create_blob.key)

    post recipes_path, params: {
      recipe: valid_recipe_params.merge(cover: create_signed_id)
    }

    created_recipe = households(:home).recipes.find_by!(title: "Savory Bowl")
    assert_redirected_to recipe_path(created_recipe)
    assert_equal create_blob, created_recipe.cover.blob

    recipe = recipes(:porridge)
    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        title: "",
        cover: fixture_file_upload("recipes/replacement-cover.png", "image/png")
      )
    }

    assert_response :unprocessable_entity
    update_signed_id = css_select("input[type='hidden'][name='recipe[cover]']").sole["value"]
    update_blob = ActiveStorage::Blob.find_signed!(update_signed_id)
    assert update_blob.service.exist?(update_blob.key)

    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        title: "Recovered Porridge",
        cover: update_signed_id
      )
    }

    assert_redirected_to recipe_path(recipe)
    assert_equal "Recovered Porridge", recipe.reload.title
    assert_equal update_blob, recipe.cover.blob
  end

  test "removal beats a staged signed cover while a new upload beats removal" do
    sign_in_as users(:one)

    post recipes_path, params: {
      recipe: valid_recipe_params.merge(
        title: "",
        cover: fixture_file_upload("recipes/cover.png", "image/png")
      )
    }

    create_signed_id = css_select("input[type='hidden'][name='recipe[cover]']").sole["value"]
    create_blob = ActiveStorage::Blob.find_signed!(create_signed_id)

    post recipes_path, params: {
      recipe: valid_recipe_params.merge(
        title: "Removed staged cover",
        cover: create_signed_id,
        remove_cover: "1"
      )
    }

    created_recipe = households(:home).recipes.find_by!(title: "Removed staged cover")
    assert_redirected_to recipe_path(created_recipe)
    assert_not created_recipe.cover.attached?
    assert_not ActiveStorage::Blob.exists?(create_blob.id)

    recipe = recipes(:porridge)
    recipe.cover.attach(fixture_file_upload("recipes/cover.png", "image/png"))
    original_blob = recipe.cover.blob

    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        title: "",
        cover: fixture_file_upload("recipes/replacement-cover.png", "image/png")
      )
    }

    update_signed_id = css_select("input[type='hidden'][name='recipe[cover]']").sole["value"]
    update_blob = ActiveStorage::Blob.find_signed!(update_signed_id)

    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        title: "Removed replacement",
        cover: update_signed_id,
        remove_cover: "1"
      )
    }

    assert_redirected_to recipe_path(recipe)
    assert_not recipe.reload.cover.attached?
    assert_not ActiveStorage::Blob.exists?(original_blob.id)
    assert_not ActiveStorage::Blob.exists?(update_blob.id)

    patch recipe_path(recipe), params: {
      recipe: persisted_recipe_params(recipe).merge(
        cover: fixture_file_upload("recipes/replacement-cover.png", "image/png"),
        remove_cover: "1"
      )
    }

    assert_redirected_to recipe_path(recipe)
    assert_predicate recipe.reload.cover, :attached?
  end

  test "Turbo structural actions rebuild without persisting" do
    sign_in_as users(:one)

    assert_no_difference [ "Recipe.count", "RecipeIngredient.count", "RecipeInstruction.count" ] do
      post recipes_path,
        params: { recipe: valid_recipe_params, add_ingredient: "1" },
        headers: turbo_stream_headers
    end

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='recipe_form']"
    assert_select "input[name*='recipe_ingredients_attributes'][name$='[name]']", count: 2

    recipe = recipes(:porridge)
    ingredient = recipe.recipe_ingredients.first

    assert_no_difference [ "Recipe.count", "RecipeIngredient.count", "RecipeInstruction.count" ] do
      patch recipe_path(recipe),
        params: {
          recipe: persisted_recipe_params(recipe),
          remove_ingredient: "0"
        },
        headers: turbo_stream_headers
    end

    assert_response :success
    assert_predicate ingredient.reload, :persisted?
    assert_select "input[name*='recipe_ingredients_attributes'][name$='[_destroy]'][value='1']"
    assert_select "input[name*='recipe_ingredients_attributes'][name$='[id]'][value='#{ingredient.id}']"
  end

  test "Turbo structural actions preserve uploaded cover and pending removal" do
    sign_in_as users(:one)

    assert_difference "ActiveStorage::Blob.count", 1 do
      post recipes_path,
        params: {
          recipe: valid_recipe_params.merge(
            cover: fixture_file_upload("recipes/cover.png", "image/png")
          ),
          add_ingredient: "1"
        },
        headers: turbo_stream_headers
    end

    assert_response :success
    hidden_cover = css_select("input[type='hidden'][name='recipe[cover]']").sole
    signed_id = hidden_cover["value"]
    assert_nil hidden_cover["id"]
    assert_select "input[type='file']#recipe_cover", count: 1
    assert_select "[id='recipe_cover']", count: 1
    assert_select "label[for='recipe_cover']", text: "Cover image"
    assert ActiveStorage::Blob.find_signed!(signed_id)

    recipe = recipes(:porridge)
    recipe.cover.attach(fixture_file_upload("recipes/cover.png", "image/png"))
    cover_blob = recipe.cover.blob

    patch recipe_path(recipe),
      params: {
        recipe: persisted_recipe_params(recipe).merge(remove_cover: "1"),
        add_instruction: "1"
      },
      headers: turbo_stream_headers

    assert_response :success
    assert_select "input[name='recipe[remove_cover]'][value='1'][checked]"
    assert_equal cover_blob, recipe.reload.cover.blob
  end

  test "final update removes an already persisted child" do
    sign_in_as users(:one)
    recipe = recipes(:porridge)
    ingredient = recipe.recipe_ingredients.first

    assert_difference "RecipeIngredient.count", -1 do
      patch recipe_path(recipe), params: {
        recipe: persisted_recipe_params(recipe).deep_merge(
          recipe_ingredients_attributes: {
            "0" => ingredient.attributes.slice("id", "amount", "unit", "name", "notes", "position").merge("_destroy" => "1"),
            "1" => recipe.recipe_ingredients.second.attributes.slice("id", "amount", "unit", "name", "notes", "position")
          }
        )
      }
    end

    assert_redirected_to recipe_path(recipe)
    assert_not RecipeIngredient.exists?(ingredient.id)
    assert_equal [ 1 ], recipe.reload.recipe_ingredients.pluck(:position)
  end

  test "remove then add structural actions save contiguous positions" do
    sign_in_as users(:one)
    recipe = recipes(:porridge)
    removed_ingredient = recipe.recipe_ingredients.first
    survivor = recipe.recipe_ingredients.second

    patch recipe_path(recipe),
      params: { recipe: persisted_recipe_params(recipe), remove_ingredient: "0" },
      headers: turbo_stream_headers
    assert_response :success

    edited_params = persisted_recipe_params(recipe).deep_merge(
      recipe_ingredients_attributes: {
        "0" => removed_ingredient.attributes.slice("id", "amount", "unit", "name", "notes").merge("_destroy" => "1"),
        "1" => survivor.attributes.slice("id", "amount", "unit", "name", "notes")
      }
    )
    patch recipe_path(recipe),
      params: { recipe: edited_params, add_ingredient: "1" },
      headers: turbo_stream_headers
    assert_response :success

    final_params = edited_params.deep_merge(
      recipe_ingredients_attributes: {
        "2" => { amount: "1", unit: "pinch", name: "Salt", notes: "" }
      }
    )
    patch recipe_path(recipe), params: { recipe: final_params }

    assert_response :see_other
    assert_equal [ 1, 2 ], recipe.reload.recipe_ingredients.pluck(:position)
    assert_equal [ survivor.id ], recipe.recipe_ingredients.where(name: "Blueberries").pluck(:id)
  end

  test "remove ingredient then add instruction saves both collections contiguously" do
    sign_in_as users(:one)
    recipe = recipes(:porridge)
    removed_ingredient = recipe.recipe_ingredients.first
    survivor = recipe.recipe_ingredients.second

    edited_params = persisted_recipe_params(recipe).deep_merge(
      recipe_ingredients_attributes: {
        "0" => removed_ingredient.attributes.slice("id", "amount", "unit", "name", "notes").merge("_destroy" => "1"),
        "1" => survivor.attributes.slice("id", "amount", "unit", "name", "notes")
      }
    )
    patch recipe_path(recipe),
      params: { recipe: edited_params, remove_ingredient: "0" },
      headers: turbo_stream_headers
    assert_response :success

    patch recipe_path(recipe),
      params: { recipe: edited_params, add_instruction: "1" },
      headers: turbo_stream_headers
    assert_response :success

    final_params = edited_params.deep_merge(
      recipe_instructions_attributes: persisted_recipe_params(recipe)[:recipe_instructions_attributes].merge(
        "2" => { body: "Enjoy." }
      )
    )
    patch recipe_path(recipe), params: { recipe: final_params }

    assert_response :see_other
    assert_equal [ 1 ], recipe.reload.recipe_ingredients.pluck(:position)
    assert_equal [ 1, 2, 3 ], recipe.recipe_instructions.pluck(:position)
  end

  test "structural removal renders contiguous ordinals and accessible labels" do
    sign_in_as users(:one)
    recipe = recipes(:porridge)

    patch recipe_path(recipe),
      params: { recipe: persisted_recipe_params(recipe), remove_instruction: "0" },
      headers: turbo_stream_headers

    assert_response :success
    assert_select "span", text: "1."
    assert_select "button[aria-label='Remove step 1']", count: 1
    assert_select "button[aria-label='Remove step 2']", count: 0
  end

  test "client-supplied duplicate positions are ignored" do
    sign_in_as users(:one)
    params = valid_recipe_params.deep_merge(
      recipe_ingredients_attributes: {
        "0" => { name: "First", position: "7" },
        "1" => { name: "Second", position: "7" }
      }
    )

    post recipes_path, params: { recipe: params }

    assert_response :see_other
    recipe = Recipe.find_by!(title: "Savory Bowl")
    assert_equal [ 1, 2 ], recipe.recipe_ingredients.pluck(:position)
  end

  test "unknown recipe id returns not found" do
    sign_in_as users(:one)

    get recipe_path(0)
    assert_response :not_found

    patch recipe_path(0), params: { recipe: valid_recipe_params }
    assert_response :not_found
  end

  private
    def valid_recipe_params
      {
        title: "Savory Bowl",
        description: "A practical test recipe",
        yield: "2 bowls",
        source_name: "Test Kitchen",
        source_url: "https://example.com/savory-bowl",
        provenance_status: "observed",
        recipe_ingredients_attributes: {
          "0" => { amount: "1", unit: "cup", name: "Lentils", notes: "", position: "1" }
        },
        recipe_instructions_attributes: {
          "0" => { body: "Combine and serve.", position: "1" }
        }
      }
    end

    def persisted_recipe_params(recipe)
      {
        title: recipe.title,
        description: recipe.description,
        yield: recipe.yield,
        source_name: recipe.source_name,
        source_url: recipe.source_url,
        provenance_status: recipe.provenance_status,
        recipe_ingredients_attributes: recipe.recipe_ingredients.each_with_index.to_h { |ingredient, index|
          [ index.to_s, ingredient.attributes.slice("id", "amount", "unit", "name", "notes", "position") ]
        },
        recipe_instructions_attributes: recipe.recipe_instructions.each_with_index.to_h { |instruction, index|
          [ index.to_s, instruction.attributes.slice("id", "body", "position") ]
        }
      }
    end

    def turbo_stream_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end
end
