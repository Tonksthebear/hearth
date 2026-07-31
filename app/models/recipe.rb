class Recipe < ApplicationRecord
  COVER_CONTENT_TYPES = %w[image/jpeg image/png image/gif].freeze
  COVER_MAX_BYTES = 10.megabytes
  IMPORT_ATTRIBUTES = %w[
    import_key title description yield source_name source_url provenance_status
    recipe_ingredients_attributes recipe_instructions_attributes
  ].freeze
  INGREDIENT_IMPORT_ATTRIBUTES = %w[amount unit name notes key].freeze
  INSTRUCTION_IMPORT_ATTRIBUTES = %w[
    body ingredient_keys duration_amount duration_unit temperature_amount temperature_unit
  ].freeze
  PROVENANCE_DESCRIPTIONS = {
    "personal" => "Created by your household.",
    "verified" => "Checked against the cited source.",
    "adapted" => "Intentionally changed from the cited source.",
    "observed" => "Recorded from practice without independent source verification."
  }.freeze

  belongs_to :household
  has_one_attached :cover do |attachable|
    attachable.variant :card, resize_to_fill: [ 640, 448 ]
    attachable.variant :hero, resize_to_fill: [ 1200, 1200 ]
  end
  has_many :planned_meals, dependent: :restrict_with_exception
  has_many :meal_logs, dependent: :restrict_with_exception
  has_many :recipe_ingredients, -> { order(:position) }, dependent: :destroy
  has_many :recipe_instructions, -> { order(:position) }, dependent: :destroy
  has_many :ingredients, through: :recipe_ingredients

  accepts_nested_attributes_for :recipe_ingredients, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :recipe_instructions, allow_destroy: true, reject_if: :all_blank

  enum :provenance_status, {
    personal: "personal",
    verified: "verified",
    adapted: "adapted",
    observed: "observed"
  }, validate: true

  validates :title, presence: true
  validates :import_key, uniqueness: { scope: :household_id }, allow_nil: true
  validates :source_name, presence: true, unless: :personal?
  validates :source_url,
    format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) },
    allow_blank: true
  validate :acceptable_cover
  validate :valid_cover_reference
  validate :valid_instruction_ingredient_references

  attr_accessor :cover_reference_invalid, :cover_uploaded_this_request, :remove_cover

  before_save :apply_cover_change
  after_save :reconcile_instruction_ingredient_references
  after_commit :purge_replaced_cover, on: %i[ create update ]
  after_rollback :clear_cover_to_purge
  scope :matching, ->(query) {
    if query.present?
      pattern = "%#{sanitize_sql_like(query.downcase, "!")}%"
      left_joins(recipe_ingredients: :ingredient)
        .where(<<~SQL.squish, pattern: pattern)
          LOWER(recipes.title) LIKE :pattern ESCAPE '!'
          OR LOWER(recipes.description) LIKE :pattern ESCAPE '!'
          OR LOWER(recipes.source_name) LIKE :pattern ESCAPE '!'
          OR LOWER(recipe_ingredients.display_name) LIKE :pattern ESCAPE '!'
          OR LOWER(ingredients.name) LIKE :pattern ESCAPE '!'
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
      import_key = normalized_attributes["import_key"].presence

      return household.recipes.create!(normalized_attributes) unless import_key

      transaction do
        recipe = household.recipes.lock.find_or_initialize_by(import_key:)
        ingredient_attributes = normalized_attributes.delete("recipe_ingredients_attributes") || []
        instruction_attributes = normalized_attributes.delete("recipe_instructions_attributes") || []
        recipe.assign_attributes(normalized_attributes)
        reconcile_import_rows(recipe.recipe_ingredients, ingredient_attributes)
        reconcile_import_rows(recipe.recipe_instructions, instruction_attributes)
        recipe.save!
        recipe
      end
    end

    private
      def normalize_import_attributes(attributes)
        raise ArgumentError, "Recipe import attributes must be a hash." unless attributes.is_a?(Hash)

        normalized = attributes.deep_stringify_keys
        reject_unknown_import_attributes!(normalized, IMPORT_ATTRIBUTES, "recipe")
        normalize_import_children!(normalized, "recipe_ingredients_attributes", INGREDIENT_IMPORT_ATTRIBUTES) do |child, position|
          {
            "display_name" => child.delete("name"),
            "display_quantity" => child.delete("amount"),
            "form_key" => child.delete("key").presence || "ingredient-#{position}"
          }.merge(child).compact
        end
        normalize_import_children!(normalized, "recipe_instructions_attributes", INSTRUCTION_IMPORT_ATTRIBUTES) do |child, _position|
          child.merge("ingredient_reference_keys" => Array(child.delete("ingredient_keys")))
        end
        normalized
      end

      def normalize_import_children!(attributes, key, allowed_attributes)
        return unless attributes.key?(key)

        children = attributes[key]
        raise ArgumentError, "#{key} must be an array of hashes." unless children.is_a?(Array)

        attributes[key] = children.map.with_index(1) do |child, position|
          raise ArgumentError, "#{key} must be an array of hashes." unless child.is_a?(Hash)

          normalized_child = child.deep_stringify_keys
          reject_unknown_import_attributes!(normalized_child, allowed_attributes, key)
          normalized_child = yield(normalized_child, position) if block_given?
          normalized_child.merge("position" => position)
        end
      end

      def reject_unknown_import_attributes!(attributes, allowed_attributes, context)
        unknown_attributes = attributes.keys - allowed_attributes
        return if unknown_attributes.empty?

        raise ArgumentError, "Unknown #{context} import attributes: #{unknown_attributes.sort.join(", ")}."
      end

      def reconcile_import_rows(association, attributes)
        existing_rows = association.to_a.sort_by(&:position)

        existing_rows.drop(attributes.length).each(&:mark_for_destruction)
        attributes.each.with_index do |row_attributes, index|
          row = existing_rows[index] || association.build
          row.assign_attributes(row_attributes)
        end
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

  def canonical_ingredient_for(name)
    normalized_name = Ingredient.normalize_name(name)
    @canonical_ingredients ||= {}
    @canonical_ingredients[normalized_name] ||= Ingredient.for(household:, name:)
  end

  def ingredient_reference_options
    active_ingredients.map do |ingredient|
      label = ingredient.display_name.presence || "Ingredient #{ingredient.position} (enter a name)"
      [ label, ingredient.form_key, { disabled: ingredient.display_name.blank? } ]
    end
  end

  def provenance_description
    PROVENANCE_DESCRIPTIONS.fetch(provenance_status)
  end

  def preserve_cover_for_form
    change = pending_cover_creation
    return self unless change
    return self unless cover_blob_acceptable?(change.blob)
    return self if change.blob.persisted?

    change.blob.save!
    change.upload
    self.cover = change.blob
    self
  rescue
    change.blob.purge if change&.blob&.persisted? && change.blob.attachments.none?
    raise
  end

  def cover_signed_id
    change = pending_cover_creation
    change.blob.signed_id if change&.blob&.persisted?
  end

  def cover_attachment_for_form
    change = pending_cover_creation
    return change.attachment if change&.blob&.persisted?

    persisted_cover_attachment
  end

  def source_label
    source_name.presence || "From your household"
  end

  private
    def valid_instruction_ingredient_references
      active_by_key = active_ingredients.index_by(&:form_key)
      destroyed_keys = recipe_ingredients.select(&:marked_for_destruction?).map(&:form_key)

      active_instructions.each do |instruction|
        next unless instruction.ingredient_reference_keys_assigned?

        keys = instruction.ingredient_reference_keys
        instruction.errors.add(:ingredient_reference_keys, "contains duplicates") if keys.uniq.length != keys.length

        unknown_keys = keys - active_by_key.keys - destroyed_keys
        instruction.errors.add(:ingredient_reference_keys, "contains an unknown ingredient") if unknown_keys.any?
        instruction.ingredient_reference_keys = keys.filter_map { |key| active_by_key[key]&.form_key }.uniq
      end
    end

    def reconcile_instruction_ingredient_references
      ingredients_by_key = active_ingredients.index_by(&:form_key)

      active_instructions.each do |instruction|
        next unless instruction.ingredient_reference_keys_assigned?

        referenced_ingredients = instruction.ingredient_reference_keys
          .filter_map { |key| ingredients_by_key[key] }
          .sort_by(&:position)
        instruction.recipe_instruction_ingredients.delete_all
        referenced_ingredients.each.with_index(1) do |ingredient, position|
          instruction.recipe_instruction_ingredients.create!(recipe: self, recipe_ingredient: ingredient, position:)
        end
      end
    end

    def valid_cover_reference
      errors.add(:cover, "is invalid") if ActiveModel::Type::Boolean.new.cast(cover_reference_invalid)
    end

    def acceptable_cover
      cover_blob_acceptable?(cover.blob) if cover.attached?
    end

    def cover_blob_acceptable?(blob)
      acceptable = true

      unless COVER_CONTENT_TYPES.include?(blob.content_type)
        message = "must be a JPEG, PNG, or GIF"
        errors.add(:cover, message) unless errors.added?(:cover, message)
        acceptable = false
      end

      if blob.byte_size > COVER_MAX_BYTES
        message = "must be 10 MB or smaller"
        errors.add(:cover, message) unless errors.added?(:cover, message)
        acceptable = false
      end

      acceptable
    end

    def apply_cover_change
      change = pending_cover_creation
      current_blob = persisted_cover_blob

      if remove_cover? && !cover_uploaded_this_request?
        @cover_blobs_to_purge = [ current_blob, change&.blob ].compact.uniq
        self.cover = nil
      elsif change && current_blob && change.blob != current_blob
        @cover_blobs_to_purge = [ current_blob ]
      end
    end

    def pending_cover_creation
      change = attachment_changes["cover"]
      change if change.is_a?(ActiveStorage::Attached::Changes::CreateOne)
    end

    def persisted_cover_blob
      persisted_cover_attachment&.blob
    end

    def persisted_cover_attachment
      ActiveStorage::Attachment.find_by(record: self, name: "cover") if persisted?
    end

    def purge_replaced_cover
      @cover_blobs_to_purge&.each(&:purge)
    ensure
      clear_cover_to_purge
    end

    def clear_cover_to_purge
      @cover_blobs_to_purge = nil
      self.cover_uploaded_this_request = nil
      self.remove_cover = nil
    end

    def cover_uploaded_this_request?
      ActiveModel::Type::Boolean.new.cast(cover_uploaded_this_request)
    end

    def remove_cover?
      ActiveModel::Type::Boolean.new.cast(remove_cover)
    end

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
