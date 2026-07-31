class Recipe < ApplicationRecord
  IMPORT_KEYS = %w[
    title description yield source_name source_url provenance_status
    recipe_ingredients_attributes recipe_instructions_attributes
  ].freeze
  INGREDIENT_IMPORT_KEYS = %w[amount unit name notes].freeze
  INSTRUCTION_IMPORT_KEYS = %w[body].freeze
  PROVENANCE_DESCRIPTIONS = {
    "personal" => "Created by your household.",
    "verified" => "Checked against the cited source.",
    "adapted" => "Intentionally changed from the cited source.",
    "observed" => "Recorded from practice without independent source verification."
  }.freeze

  belongs_to :household
  has_many :planned_meals, dependent: :restrict_with_exception
  has_many :meal_logs, dependent: :restrict_with_exception
  has_many :recipe_ingredients, -> { order(:position) }, dependent: :destroy
  has_many :recipe_instructions, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :recipe_ingredients, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :recipe_instructions, allow_destroy: true, reject_if: :all_blank

  enum :provenance_status, {
    personal: "personal",
    verified: "verified",
    adapted: "adapted",
    observed: "observed"
  }, validate: true

  validates :title, presence: true
  validates :source_name, presence: true, unless: :personal?
  validates :source_url,
    format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) },
    allow_blank: true
  scope :matching, ->(query) {
    if query.present?
      pattern = "%#{sanitize_sql_like(query.downcase, "!")}%"
      left_joins(:recipe_ingredients)
        .where(<<~SQL.squish, pattern: pattern)
          LOWER(recipes.title) LIKE :pattern ESCAPE '!'
          OR LOWER(recipes.description) LIKE :pattern ESCAPE '!'
          OR LOWER(recipes.source_name) LIKE :pattern ESCAPE '!'
          OR LOWER(recipe_ingredients.name) LIKE :pattern ESCAPE '!'
        SQL
        .distinct
    else
      all
    end
  }

  scope :with_provenance_status, ->(status) {
    status.present? ? where(provenance_status: status) : all
  }

  class << self
    def import!(household:, attributes:)
      normalized_attributes = normalize_import_attributes(attributes)

      household.recipes.create!(normalized_attributes)
    end

    private
      def normalize_import_attributes(attributes)
        raise ArgumentError, "Recipe import attributes must be a hash." unless attributes.is_a?(Hash)

        normalized = attributes.deep_stringify_keys
        reject_unknown_import_keys!(normalized, IMPORT_KEYS, "recipe")
        normalize_import_children!(normalized, "recipe_ingredients_attributes", INGREDIENT_IMPORT_KEYS)
        normalize_import_children!(normalized, "recipe_instructions_attributes", INSTRUCTION_IMPORT_KEYS)
        normalized
      end

      def normalize_import_children!(attributes, key, allowed_keys)
        return unless attributes.key?(key)

        children = attributes[key]
        raise ArgumentError, "#{key} must be an array of hashes." unless children.is_a?(Array)

        attributes[key] = children.map.with_index(1) do |child, position|
          raise ArgumentError, "#{key} must be an array of hashes." unless child.is_a?(Hash)

          normalized_child = child.deep_stringify_keys
          reject_unknown_import_keys!(normalized_child, allowed_keys, key)
          normalized_child.merge("position" => position)
        end
      end

      def reject_unknown_import_keys!(attributes, allowed_keys, context)
        unknown_keys = attributes.keys - allowed_keys
        return if unknown_keys.empty?

        raise ArgumentError, "Unknown #{context} import keys: #{unknown_keys.sort.join(", ")}."
      end
  end

  def add_ingredient
    recipe_ingredients.build(position: active_ingredients.size + 1)
    normalize_positions
  end

  def add_instruction
    recipe_instructions.build(position: active_instructions.size + 1)
    normalize_positions
  end

  def remove_ingredient(index)
    remove_nested_record(recipe_ingredients, index)
    normalize_positions
    self
  end

  def remove_instruction(index)
    remove_nested_record(recipe_instructions, index)
    normalize_positions
    self
  end

  def normalize_positions
    active_ingredients.each.with_index(1) { |ingredient, position| ingredient.position = position }
    active_instructions.each.with_index(1) { |instruction, position| instruction.position = position }
    self
  end

  def ensure_form_rows
    add_ingredient if active_ingredients.empty?
    add_instruction if active_instructions.empty?
    self
  end

  def provenance_description
    PROVENANCE_DESCRIPTIONS.fetch(provenance_status)
  end

  def source_label
    source_name.presence || "From your household"
  end

  private
    def active_ingredients
      recipe_ingredients.reject(&:marked_for_destruction?)
    end

    def active_instructions
      recipe_instructions.reject(&:marked_for_destruction?)
    end

    def remove_nested_record(association, index)
      record = association.to_a.fetch(Integer(index, 10))

      if record.persisted?
        record.mark_for_destruction
      else
        association.delete(record)
      end
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid nested recipe row."
    end
end
