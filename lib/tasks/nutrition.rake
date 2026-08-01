namespace :nutrition do
  desc "Import per-100-gram nutrient values from USDA FoodData Central"
  task :import_fdc, [ :ingredient_id, :food_id ] => :environment do |_task, args|
    ingredient = Ingredient.find(args.fetch(:ingredient_id))
    Ingredient::FoodDataCentralImport.new(ingredient:, food_id: args.fetch(:food_id)).import!
    puts "Imported FoodData Central nutrition for #{ingredient.name}."
  end
end
