require "test_helper"
require "yaml"
require Rails.root.join("db/migrate/20260825150200_create_muscle_taxonomy")

class MuscleTest < ActiveSupport::TestCase
  test "migration defaults catalog yaml and fixtures describe the same catalog" do
    migration = CreateMuscleTaxonomy::DEFAULT_MUSCLES
    yaml = Muscle.load_catalog(Muscle::CATALOG_PATH.read)
    fixtures = Muscle.displayed.map { |row|
      {
        key: row.key,
        name: row.name,
        muscle_group: row.muscle_group,
        aliases: row.aliases,
        display_position: row.display_position
      }
    }

    assert_equal migration, yaml
    assert_equal yaml, Muscle::DEFAULTS
    assert_equal Muscle::DEFAULTS, fixtures
  end

  test "default reconciliation is idempotent and preserves exactly nineteen rows" do
    assert_no_difference "Muscle.count" do
      2.times { Muscle.ensure_defaults! }
    end
    assert_equal 19, Muscle.count
  end

  test "key and muscle group reject unknown values at validation and check constraint" do
    muscle = Muscle.new(
      key: "unknown",
      name: "Unknown",
      muscle_group: "torso",
      aliases: [],
      display_position: 99
    )

    assert_not muscle.valid?
    assert_includes muscle.errors[:key], "is not included in the list"
    assert_includes muscle.errors[:muscle_group], "is not included in the list"

    now = Time.current
    assert_raises ActiveRecord::StatementInvalid do
      Muscle.insert!({
        key: "unknown",
        name: "Unknown",
        muscle_group: "legs",
        aliases: [],
        display_position: 99,
        created_at: now,
        updated_at: now
      })
    end
    assert_raises ActiveRecord::StatementInvalid do
      muscles(:calves).update_column(:muscle_group, "torso")
    end
  end

  test "stable keys cannot change while display details can" do
    muscle = muscles(:quadriceps)
    assert_not muscle.update(key: "glutes")
    assert_includes muscle.errors[:key], "cannot change"
    muscle.reload
    assert muscle.update(name: "Quadriceps group")
  end

  test "display position is unique and greater than zero" do
    muscle = muscles(:calves)
    assert_not muscle.update(display_position: 0)
    assert_includes muscle.errors[:display_position], "must be greater than 0"
    assert_not muscle.update(display_position: muscles(:quadriceps).display_position)
    assert_includes muscle.errors[:display_position], "has already been taken"

    assert_raises ActiveRecord::StatementInvalid do
      muscle.update_column(:display_position, 0)
    end
    assert_raises ActiveRecord::RecordNotUnique do
      muscle.update_column(:display_position, muscles(:quadriceps).display_position)
    end
  end

  test "displayed returns head to toe order" do
    assert_equal Muscle::DEFAULTS.map { |row| row.fetch(:key) }, Muscle.displayed.map(&:key)
    assert_equal (1..19).to_a, Muscle.displayed.map(&:display_position)
  end

  test "resolve source name matches exact one to one aliases only" do
    assert_equal muscles(:quadriceps), Muscle.resolve_source_name("Quads")
    assert_nil Muscle.resolve_source_name("Posterior Chain")
    assert_nil Muscle.resolve_source_name("Cardio")
    assert_nil Muscle.resolve_source_name("quads")
  end

  test "no alias string appears on two muscles" do
    aliases = Muscle.displayed.flat_map(&:aliases)
    assert_equal aliases, aliases.uniq
  end

  test "seeded aliases equal the overrides muscle aliases block" do
    overrides = YAML.safe_load(
      Rails.root.join("config/workout_guide_overrides.yml").read,
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    seeded = Muscle.displayed.each_with_object({}) { |muscle, mapping|
      muscle.aliases.each { |alias_name| mapping[alias_name] = muscle.key }
    }

    assert_equal overrides.fetch("muscle_aliases"), seeded
  end

  test "catalog yaml rejects a duplicate mapping key" do
    duplicated = Muscle::CATALOG_PATH.read.sub(
      /^quadriceps:\n(?:  .*\n)+/,
      "\\0quadriceps:\n  name: Dup\n  muscle_group: legs\n  aliases: []\n  display_position: 99\n"
    )

    assert_includes Muscle.duplicate_mapping_keys(Psych.parse(duplicated)), "quadriceps"
    error = assert_raises(ArgumentError) { Muscle.load_catalog(duplicated) }
    assert_includes error.message, "quadriceps"
  end
end
