require "net/http"

class Ingredient::FoodDataCentralImport
  ENDPOINT = "https://api.nal.usda.gov/fdc/v1/food"
  MAPPINGS = {
    1008 => [ "energy", "KCAL" ],
    1003 => [ "protein", "G" ],
    1005 => [ "carbohydrates", "G" ],
    1004 => [ "fat", "G" ],
    1079 => [ "fiber", "G" ],
    1093 => [ "sodium", "MG" ]
  }.freeze

  class ImportError < StandardError; end

  attr_reader :ingredient, :food_id, :api_key, :requester

  def initialize(ingredient:, food_id:, api_key: nil, requester: nil)
    @ingredient = ingredient
    @food_id = food_id.to_s.strip
    @api_key = api_key.presence || Rails.application.credentials.dig(:food_data_central, :api_key).presence || ENV["FDC_API_KEY"].presence
    @requester = requester || method(:request)
  end

  def import!
    raise ArgumentError, "A FoodData Central food ID is required." if food_id.blank?
    raise ImportError, "FoodData Central API key is not configured." if api_key.blank?

    attributes = mapped_values(fetch_payload)
    raise ImportError, "FoodData Central returned no recognized nutrient values." if attributes.empty?

    Ingredient.transaction do
      ingredient.update!(
        food_data_central_id: food_id,
        nutrition_source_name: "USDA FoodData Central",
        nutrition_provenance_status: :verified
      )
      attributes.each do |nutrient_key, amount|
        nutrient = Nutrient.find_by!(key: nutrient_key)
        ingredient.ingredient_nutrient_values.find_or_initialize_by(nutrient:).update!(amount_per_100_grams: amount)
      end
    end
    ingredient
  rescue JSON::ParserError, KeyError, TypeError
    raise ImportError, "FoodData Central returned an invalid response."
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError
    raise ImportError, "FoodData Central could not be reached."
  end

  private
    def fetch_payload
      uri = URI("#{ENDPOINT}/#{URI.encode_www_form_component(food_id)}")
      uri.query = URI.encode_www_form(api_key: api_key)
      response = requester.call(uri)
      raise ImportError, "FoodData Central request failed (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, { "Accept" => "application/json" })
      end
    end

    def mapped_values(payload)
      nutrients = payload.fetch("foodNutrients")
      raise TypeError unless nutrients.is_a?(Array)

      nutrients.each_with_object({}) do |row, mapped|
        nutrient = row.fetch("nutrient")
        mapping = MAPPINGS[nutrient.fetch("id").to_i]
        next unless mapping

        key, expected_unit = mapping
        unit = nutrient.fetch("unitName").to_s.upcase
        raise ImportError, "FoodData Central returned an unsupported unit for #{key}." unless unit == expected_unit

        mapped[key] = BigDecimal(row.fetch("amount").to_s)
      end
    end
end
