require "psych"
require "yaml"

class WorkoutGuide::MuscleMapping
  OVERRIDES_PATH = Rails.root.join("config/workout_guide_overrides.yml")

  class << self
    def targets_for(slug:, primary_muscle:, secondary_muscles:)
      default.targets_for(slug:, primary_muscle:, secondary_muscles:)
    end

    def expand(source_name, role:)
      default.expand(source_name, role:)
    end

    def default
      @default ||= new
    end
  end

  def initialize(path: OVERRIDES_PATH)
    text = Pathname(path).read
    duplicates = Muscle.duplicate_mapping_keys(Psych.parse(text))
    raise ArgumentError, "Duplicate override keys: #{duplicates.join(", ")}" if duplicates.any?

    @overrides = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def targets_for(slug:, primary_muscle:, secondary_muscles:)
    raise ArgumentError, "Unknown workout guide exercise slug: #{slug}" unless exercises.key?(slug)

    override = exercises.fetch(slug)
    if override.key?("muscle_targets")
      return override_targets(override.fetch("muscle_targets"), slug)
    end

    pairs = expand(primary_muscle, role: "primary")
    Array(secondary_muscles).each do |name|
      pairs.concat(expand(name, role: "secondary"))
    end
    merge_by_precedence(pairs)
  end

  def expand(source_name, role:)
    return [] if unmapped.include?(source_name)

    if aliases.key?(source_name)
      muscle = Muscle.resolve_source_name(source_name)
      raise ArgumentError, "Unmapped source muscle name: #{source_name}" unless muscle

      return [ { muscle:, role: incoming_role(role) } ]
    end

    compound = compounds[source_name]
    raise ArgumentError, "Unmapped source muscle name: #{source_name}" unless compound

    list_name = incoming_role(role) == "primary" ? "as_primary" : "as_secondary"
    compound.fetch(list_name).map { |entry|
      {
        muscle: Muscle.find_by!(key: entry.fetch("muscle_key")),
        role: entry.fetch("role")
      }
    }
  end

  private
    def exercises
      @overrides.fetch("exercises")
    end

    def aliases
      @overrides.fetch("muscle_aliases")
    end

    def compounds
      @overrides.fetch("muscle_compounds")
    end

    def unmapped
      @overrides.fetch("muscle_unmapped")
    end

    def override_targets(list, slug)
      keys = list.map { |entry| entry.fetch("muscle_key") }
      raise ArgumentError, "Duplicate muscle_key in #{slug} override: #{keys.tally.select { |_key, count| count > 1 }.keys.join(", ")}" if keys.size != keys.uniq.size

      list.map { |entry|
        role = entry.fetch("role")
        raise ArgumentError, "Invalid role #{role.inspect} for #{slug}" unless ExerciseMuscleTarget::ROLES.include?(role)

        {
          muscle: Muscle.find_by!(key: entry.fetch("muscle_key")),
          role: role
        }
      }
    end

    def merge_by_precedence(pairs)
      pairs
        .group_by { |pair| pair.fetch(:muscle).key }
        .map { |_key, group|
          group.min_by { |pair| ExerciseMuscleTarget::ROLE_PRECEDENCE.fetch(pair.fetch(:role)) }
        }
        .sort_by { |pair| pair.fetch(:muscle).display_position }
    end

    def incoming_role(role)
      value = role.to_s
      raise ArgumentError, "Invalid expansion role: #{role.inspect}" unless %w[primary secondary].include?(value)

      value
    end
end
