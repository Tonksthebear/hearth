class Exercise::SourceMerge
  class MappingError < StandardError; end

  Result = Data.define(:status, :exercise, :reasons, :changes)

  SCALAR_FIELDS = %w[name modality movement_pattern equipment].freeze
  ATTRIBUTION_FIELDS = %w[creator creator_url license license_url source_name source_url change_note].freeze

  def self.mark_removed!(household:, present_source_keys:, source_namespace:)
    present = Array(present_source_keys).filter_map { |key| key.to_s.presence }.to_set

    household.exercises.from_source_namespace(source_namespace).filter_map { |exercise|
      next if present.include?(exercise.source_key)

      if exercise.source_removed_at.blank?
        exercise.update!(source_removed_at: Time.current)
      end

      Result.new(
        status: "source_removed",
        exercise: exercise.reload,
        reasons: [],
        changes: []
      )
    }
  end

  def initialize(household:, record:)
    @household = household
    @record = record
    @applied_visual_keys = Set.new
  end

  def merge_record!
    parsed = parse_record!
    existing = household.exercises.find_by(source_key: parsed.fetch(:source_key))

    if existing.nil?
      return skip_result if household.exercises.exists?(name: parsed.fetch(:name))

      create_record!(parsed)
    else
      update_record!(existing, parsed)
    end
  rescue MappingError, ActiveRecord::RecordInvalid, ArgumentError, KeyError, TypeError => error
    Result.new(status: "failed", exercise: nil, reasons: [ error.message ], changes: [])
  end

  private
    attr_reader :household, :record

    def skip_result
      Result.new(status: "skipped", exercise: nil, reasons: [], changes: [])
    end

    def create_record!(parsed)
      Exercise.transaction do
        exercise = household.exercises.new(
          source_key: parsed.fetch(:source_key),
          source_version: parsed[:source_version],
          name: parsed.fetch(:name),
          modality: parsed.fetch(:modality),
          movement_pattern: parsed.fetch(:movement_pattern),
          equipment: parsed[:equipment],
          source_snapshot: empty_snapshot
        )
        parsed.fetch(:targets).each do |key, role|
          exercise.exercise_muscle_targets.build(muscle: Muscle.find_by!(key:), role:)
        end
        parsed.fetch(:visuals).each { |incoming| create_visual!(exercise, incoming) }
        exercise.normalize_positions
        persist!(exercise)
        exercise.source_snapshot = snapshot_after_apply(exercise.reload, parsed, empty_snapshot)
        persist!(exercise)
        Result.new(status: "created", exercise: exercise.reload, reasons: [], changes: [ "created" ])
      end
    end

    def update_record!(exercise, parsed)
      Exercise.transaction do
        reasons = []
        changes = []
        snapshot = snapshot_for(exercise)
        original_visuals = snapshot["visuals"].deep_dup
        @applied_visual_keys = Set.new

        if exercise.source_removed_at.present?
          exercise.source_removed_at = nil
          changes << "source_removed_at"
        end

        merge_scalars!(exercise, parsed, snapshot, reasons, changes)
        merge_targets!(exercise, parsed.fetch(:targets), snapshot, changes)
        merge_visuals!(exercise, parsed.fetch(:visuals), snapshot, changes)
        merge_attribution!(snapshot, parsed.fetch(:attribution), changes)

        if exercise.source_version != parsed[:source_version]
          exercise.source_version = parsed[:source_version]
          changes << "source_version"
        end

        exercise.source_snapshot = snapshot
        exercise.normalize_positions
        persist!(exercise)
        refreshed = snapshot_after_apply(exercise.reload, parsed, snapshot, original_visuals, @applied_visual_keys)
        if exercise.source_snapshot != refreshed
          exercise.source_snapshot = refreshed
          persist!(exercise)
        end

        Result.new(
          status: result_status(changes),
          exercise: exercise.reload,
          reasons: reasons.uniq,
          changes: changes.uniq
        )
      end
    end

    def result_status(changes)
      applied = Array(changes).reject { |change| change.to_s.start_with?("snapshot.") }
      applied.any? ? "updated" : "preserved"
    end

    def parse_record!
      data = deep_hash(record)
      source_key = data["source_key"].to_s.presence
      raise MappingError, "source_key is required" if source_key.blank?

      name = data["name"].to_s.presence
      raise MappingError, "name is required" if name.blank?

      modality = data["modality"].to_s.presence
      movement_pattern = data["movement_pattern"].to_s.presence
      raise MappingError, "modality is required" if modality.blank?
      raise MappingError, "movement_pattern is required" if movement_pattern.blank?
      raise MappingError, "unknown modality" unless Exercise::MODALITIES.include?(modality)
      raise MappingError, "unknown movement_pattern" unless Exercise::MOVEMENT_PATTERNS.include?(movement_pattern)

      {
        source_key:,
        source_version: data["source_version"]&.to_s.presence,
        name:,
        modality:,
        movement_pattern:,
        equipment: data["equipment"],
        targets: parse_targets!(data["targets"]),
        visuals: parse_visuals!(data["visuals"]),
        attribution: parse_attribution(data["attribution"])
      }
    end

    def parse_targets!(raw)
      return {} if raw.blank?

      entries = if raw.is_a?(Hash)
        raw.map { |key, role| { "muscle_key" => key, "role" => role } }
      else
        Array(raw).map { |entry| deep_hash(entry) }
      end

      entries.each_with_object({}) { |entry, mapped|
        muscle = entry["muscle"]
        muscle_key = muscle.respond_to?(:key) ? muscle.key : entry["muscle_key"]
        role = entry["role"].to_s.presence
        raise MappingError, "target role is required" if role.blank?
        raise MappingError, "unknown target role" unless ExerciseMuscleTarget::ROLES.include?(role)

        resolved = Muscle.find_by(key: muscle_key.to_s)
        raise MappingError, "unknown muscle_key #{muscle_key.inspect}" unless resolved

        mapped[resolved.key] = role
      }
    end

    def parse_visuals!(raw)
      return [] if raw.blank?

      Array(raw).map { |entry|
        visual = deep_hash(entry)
        source_key = visual["source_key"].to_s.presence
        raise MappingError, "visual source_key is required" if source_key.blank?

        kind = visual["kind"].to_s.presence
        raise MappingError, "visual kind is required" if kind.blank?
        raise MappingError, "unknown visual kind" unless ExerciseVisual::KINDS.include?(kind)

        alt_text = visual["alt_text"].to_s
        raise MappingError, "visual alt_text is required" if alt_text.blank?

        items = Array(visual["items"]).map { |item_entry|
          item = deep_hash(item_entry)
          identifier = item["source_identifier"].to_s.presence
          raise MappingError, "source_identifier is required" if identifier.blank?

          checksum = item["source_checksum"].to_s.presence
          raise MappingError, "source_checksum is required" if checksum.blank?

          {
            source_identifier: identifier,
            source_checksum: checksum,
            file: item["file"]
          }
        }
        raise MappingError, "visual items are required" if items.empty?

        {
          source_key:,
          kind:,
          alt_text:,
          caption: visual["caption"],
          frame_interval_ms: visual["frame_interval_ms"],
          provenance_status: visual["provenance_status"].to_s.presence,
          items:
        }
      }
    end

    def parse_attribution(raw)
      data = deep_hash(raw)
      ATTRIBUTION_FIELDS.index_with { |field| data[field] }
    end

    def merge_scalars!(exercise, parsed, snapshot, reasons, changes)
      snapshot["scalars"] ||= {}

      SCALAR_FIELDS.each do |field|
        incoming = parsed[field.to_sym]
        current = exercise.public_send(field)
        base = snapshot["scalars"][field]

        if field == "name" && !values_equal?(incoming, current) && !values_equal?(incoming, base) && name_taken_by_other?(exercise, incoming)
          reasons << "name_conflict"
          next
        end

        if values_equal?(current, base) && !values_equal?(current, incoming)
          exercise.public_send("#{field}=", incoming)
          changes << field
        end

        unless values_equal?(snapshot["scalars"][field], incoming)
          snapshot["scalars"][field] = incoming
        end
      end
    end

    def merge_targets!(exercise, incoming_targets, snapshot, changes)
      snapshot["targets"] ||= {}
      snapshot["removed_target_keys"] ||= []
      base_targets = snapshot["targets"]
      removed = snapshot["removed_target_keys"]
      current = current_targets(exercise)

      base_targets.each_key do |key|
        next if current.key?(key) || removed.include?(key)

        removed << key
        changes << "targets.removed"
      end

      incoming_targets.each do |key, role|
        next if removed.include?(key)

        existing = current[key]
        if existing.nil?
          exercise.exercise_muscle_targets.build(muscle: Muscle.find_by!(key:), role:)
          changes << "targets.added"
        elsif base_targets.key?(key)
          next if existing.role != base_targets[key]
          next if existing.role == role

          existing.role = role
          changes << "targets.updated"
        end
      end

      current = current_targets(exercise)
      base_targets.each do |key, base_role|
        next if incoming_targets.key?(key)

        existing = current[key]
        next unless existing
        next if existing.role != base_role

        destroy_target!(existing)
        changes << "targets.obsolete"
      end

      snapshot["targets"] = next_target_base(base_targets, incoming_targets, current_targets(exercise), removed)
    end

    def next_target_base(base_targets, incoming_targets, current, removed)
      next_base = {}

      incoming_targets.each do |key, role|
        next_base[key] = role unless removed.include?(key)
      end

      base_targets.each do |key, role|
        existing = current[key]
        next unless existing
        next if incoming_targets.key?(key)
        next if existing.role == role

        next_base[key] = role
      end

      next_base
    end

    def merge_visuals!(exercise, incoming_visuals, snapshot, changes)
      snapshot["visuals"] ||= {}
      snapshot["removed_visual_keys"] ||= []
      base_visuals = snapshot["visuals"]
      tombstones = snapshot["removed_visual_keys"]
      incoming_by_key = incoming_visuals.index_by { |visual| visual[:source_key] }
      current = current_source_visuals(exercise)

      base_visuals.each_key do |key|
        next unless current[key].nil?
        next if tombstones.include?(key)

        tombstones << key
        changes << "visuals.tombstone"
      end

      base_visuals.each do |key, entry|
        visual = current[key]
        next unless visual
        next if incoming_by_key[key]
        next if household_changed_visual?(visual, entry)

        destroy_visual!(visual)
        current.delete(key)
        changes << "visuals.destroyed"
      end

      incoming_visuals.each do |incoming|
        key = incoming[:source_key]
        next if current[key] || tombstones.include?(key)

        create_visual!(exercise, incoming)
        current = current_source_visuals(exercise)
        changes << "visuals.created"
      end

      incoming_visuals.each do |incoming|
        visual = current[incoming[:source_key]]
        next unless visual
        next if visual.new_record?

        base = base_visuals[incoming[:source_key]]
        next if household_changed_visual?(visual, base)
        next unless upstream_changed_visual?(incoming, base)

        apply_visual_update!(visual, incoming, base)
        @applied_visual_keys << incoming[:source_key]
        changes << "visuals.updated"
      end

      snapshot["visuals"] = next_visual_base(base_visuals, incoming_by_key, current_source_visuals(exercise), tombstones)
    end

    def next_visual_base(base_visuals, incoming_by_key, current, tombstones)
      next_base = {}
      applied = Array(@applied_visual_keys)

      incoming_by_key.each do |key, incoming|
        visual = current[key]
        next unless visual
        next if tombstones.include?(key)

        if applied.include?(key) || visual.new_record?
          next_base[key] = incoming_visual_base(visual, incoming)
        elsif household_changed_visual?(visual, base_visuals[key])
          next_base[key] = base_visuals[key]
        else
          next_base[key] = incoming_visual_base(visual, incoming)
        end
      end

      base_visuals.each do |key, entry|
        visual = current[key]
        next unless visual
        next if incoming_by_key[key]
        next unless household_changed_visual?(visual, entry)

        next_base[key] = entry
      end

      next_base
    end

    def incoming_visual_base(visual, incoming)
      {
        "alt_text" => incoming[:alt_text],
        "caption" => incoming[:caption],
        "frame_interval_ms" => incoming[:frame_interval_ms],
        "items" => incoming[:items].map { |incoming_item|
          item = visual.sorted_items.find { |row| row.source_identifier == incoming_item[:source_identifier] }
          {
            "source_identifier" => incoming_item[:source_identifier],
            "source_checksum" => incoming_item[:source_checksum],
            "content_digest" => attached_digest(item)
          }
        }
      }
    end

    def household_changed_visual?(visual, base)
      return false if base.blank?

      return true unless values_equal?(visual.alt_text, base["alt_text"])
      return true unless values_equal?(visual.caption, base["caption"])
      return true unless values_equal?(visual.frame_interval_ms, base["frame_interval_ms"])

      current_pairs = visual.sorted_items.map { |item|
        [ item.source_identifier, attached_digest(item) ]
      }
      base_pairs = Array(base["items"]).map { |item|
        [ item["source_identifier"], item["content_digest"] ]
      }
      current_pairs != base_pairs
    end

    def upstream_changed_visual?(incoming, base)
      return true if base.blank?

      return true unless values_equal?(incoming[:alt_text], base["alt_text"])
      return true unless values_equal?(incoming[:caption], base["caption"])
      return true unless values_equal?(incoming[:frame_interval_ms], base["frame_interval_ms"])

      incoming_pairs = incoming[:items].map { |item|
        [ item[:source_identifier], item[:source_checksum] ]
      }
      base_pairs = Array(base["items"]).map { |item|
        [ item["source_identifier"], item["source_checksum"] ]
      }
      incoming_pairs != base_pairs
    end

    def create_visual!(exercise, incoming)
      visual = exercise.exercise_visuals.build(
        source_key: incoming[:source_key],
        kind: incoming[:kind],
        alt_text: incoming[:alt_text],
        caption: incoming[:caption],
        frame_interval_ms: incoming[:kind] == "frame_sequence" ? incoming[:frame_interval_ms] : nil,
        provenance_status: incoming[:provenance_status] || "personal",
        position: next_visual_position(exercise)
      )
      incoming[:items].each_with_index do |incoming_item, index|
        raise MappingError, "file is required for a new visual item" if incoming_item[:file].blank?

        item = visual.exercise_visual_items.build(
          position: index + 1,
          source_identifier: incoming_item[:source_identifier],
          source_checksum: incoming_item[:source_checksum]
        )
        item.file.attach(incoming_item[:file])
      end
      visual
    end

    def apply_visual_update!(visual, incoming, base)
      visual.alt_text = incoming[:alt_text]
      visual.caption = incoming[:caption]
      visual.kind = incoming[:kind]
      visual.frame_interval_ms = visual.frame_sequence? ? incoming[:frame_interval_ms] : nil

      current_items = visual.exercise_visual_items.reject(&:marked_for_destruction?).index_by(&:source_identifier)
      base_items = Array(base&.fetch("items", nil)).index_by { |item| item["source_identifier"] }

      incoming[:items].each_with_index do |incoming_item, index|
        item = current_items[incoming_item[:source_identifier]]
        if item.nil?
          raise MappingError, "file is required for a new visual item" if incoming_item[:file].blank?

          item = visual.exercise_visual_items.build(
            position: index + 1,
            source_identifier: incoming_item[:source_identifier],
            source_checksum: incoming_item[:source_checksum]
          )
          item.file.attach(incoming_item[:file])
        else
          item.position = index + 1
          base_checksum = base_items.dig(incoming_item[:source_identifier], "source_checksum")
          if incoming_item[:source_checksum] != base_checksum
            raise MappingError, "file is required to replace a visual item" if incoming_item[:file].blank?

            item.file.attach(incoming_item[:file])
            item.source_checksum = incoming_item[:source_checksum]
          end
        end
      end

      current_items.each do |identifier, item|
        next if incoming[:items].any? { |incoming_item| incoming_item[:source_identifier] == identifier }

        if item.persisted?
          item.mark_for_destruction
        else
          visual.exercise_visual_items.delete(item)
        end
      end

      visual.normalize_positions
    end

    def merge_attribution!(snapshot, incoming, changes)
      current = snapshot["attribution"] || {}
      return if current == incoming

      snapshot["attribution"] = incoming
      changes << "attribution"
    end

    def snapshot_after_apply(exercise, parsed, snapshot, original_visuals = nil, applied_visual_keys = nil)
      original_visuals ||= snapshot["visuals"] || {}
      applied = Array(applied_visual_keys || @applied_visual_keys)
      next_snapshot = empty_snapshot.merge(deep_hash(snapshot))
      next_snapshot["scalars"] = if snapshot["scalars"].blank?
        SCALAR_FIELDS.index_with { |field| parsed[field.to_sym] }
      else
        snapshot["scalars"]
      end
      next_snapshot["targets"] = if snapshot["targets"].blank?
        parsed.fetch(:targets)
      else
        snapshot["targets"]
      end
      next_snapshot["removed_target_keys"] = Array(snapshot["removed_target_keys"])
      next_snapshot["removed_visual_keys"] = Array(snapshot["removed_visual_keys"])
      next_snapshot["attribution"] = parsed.fetch(:attribution)

      incoming_by_key = parsed.fetch(:visuals).index_by { |visual| visual[:source_key] }
      current = current_source_visuals(exercise)
      next_visuals = {}

      incoming_by_key.each do |key, incoming|
        visual = current[key]
        next unless visual
        next if next_snapshot["removed_visual_keys"].include?(key)

        if applied.include?(key) || visual.id_previously_changed? || original_visuals[key].blank?
          next_visuals[key] = incoming_visual_base(visual, incoming)
        elsif household_changed_visual?(visual, original_visuals[key])
          next_visuals[key] = original_visuals[key]
        else
          next_visuals[key] = incoming_visual_base(visual, incoming)
        end
      end

      original_visuals.each do |key, entry|
        visual = current[key]
        next unless visual
        next if incoming_by_key[key]
        next unless household_changed_visual?(visual, entry)

        next_visuals[key] = entry
      end

      next_snapshot["visuals"] = next_visuals
      next_snapshot
    end

    def snapshot_for(exercise)
      empty_snapshot.merge(deep_hash(exercise.source_snapshot))
    end

    def empty_snapshot
      {
        "scalars" => {},
        "targets" => {},
        "removed_target_keys" => [],
        "visuals" => {},
        "removed_visual_keys" => [],
        "attribution" => {}
      }
    end

    def persist!(exercise)
      exercise.save!
      persist_targets!(exercise)
    end

    def persist_targets!(exercise)
      exercise.exercise_muscle_targets.each do |target|
        if target.marked_for_destruction? || target.destroyed?
          target.destroy! if target.persisted? && !target.destroyed?
        elsif target.new_record? || target.changed?
          target.save!
        end
      end
    end

    def current_targets(exercise)
      exercise.exercise_muscle_targets.reject(&:marked_for_destruction?).index_by { |target|
        target.muscle.key
      }
    end

    def current_source_visuals(exercise)
      exercise.exercise_visuals.reject { |visual|
        visual.marked_for_destruction? || visual.destroyed?
      }.select { |visual|
        visual.source_key.present?
      }.index_by(&:source_key)
    end

    def destroy_target!(target)
      if target.persisted?
        target.destroy!
      else
        target.exercise.exercise_muscle_targets.delete(target)
      end
    end

    def destroy_visual!(visual)
      exercise = visual.exercise
      if visual.persisted?
        visual.destroy!
      else
        exercise.exercise_visuals.delete(visual)
      end
      exercise.exercise_visuals.reset
    end

    def next_visual_position(exercise)
      exercise.exercise_visuals.reject(&:marked_for_destruction?).map(&:position).compact.max.to_i + 1
    end

    def attached_digest(item)
      return unless item&.file&.attached?

      item.file.blob.checksum
    end

    def name_taken_by_other?(exercise, name)
      household.exercises.where(name:).where.not(id: exercise.id).exists?
    end

    def values_equal?(left, right)
      normalize_value(left) == normalize_value(right)
    end

    def normalize_value(value)
      return if value.nil?

      value.to_s
    end

    def deep_hash(value)
      case value
      when Hash
        value.deep_stringify_keys
      when ActionController::Parameters
        value.to_unsafe_h.deep_stringify_keys
      when nil
        {}
      else
        value.respond_to?(:to_h) ? value.to_h.deep_stringify_keys : {}
      end
    end
end
