require "test_helper"
require "digest"
require "json"
require "psych"
require "yaml"

class WorkoutGuideBundleContractTest < ActiveSupport::TestCase
  BUNDLE = Rails.root.join("vendor/workout_guide")
  OVERRIDES_PATH = Rails.root.join("config/workout_guide_overrides.yml")
  DOCUMENT_PATH = Rails.root.join("docs/workout-guide-catalog-contract.md")

  RECORD_KEYS = %w[
    attribution equipment exerciseType frames id isStretch name primaryMuscle secondaryMuscles slug
  ].freeze
  FRAME_KEYS = %w[attribution format height index path width].freeze
  ATTRIBUTION_KEYS = %w[creator creatorUrl license licenseUrl].freeze
  SOURCE_KEYS = %w[changes license licenseUrl name url].freeze
  OVERRIDE_KEYS = %w[
    contract_version exercises muscle_aliases muscle_compounds muscle_unmapped source
  ].freeze
  EXERCISE_KEYS = %w[modality movement_pattern].freeze
  EXERCISE_KEYS_WITH_TARGETS = %w[modality movement_pattern muscle_targets].freeze
  TARGET_KEYS = %w[muscle_key role].freeze
  COMPOUND_KEYS = %w[as_primary as_secondary].freeze
  ROLES = %w[primary secondary stabilizer].freeze
  ROLE_RANK = { "primary" => 0, "secondary" => 1, "stabilizer" => 2 }.freeze
  UNMAPPED_LABELS = %w[Cardio Mobility].freeze
  PROHIBITED_NAMES = %w[package.json package-lock.json].freeze
  PROHIBITED_DIRECTORIES = %w[node_modules].freeze
  PROHIBITED_EXTENSIONS = %w[.mjs .svg .ts].freeze

  test "the pinned bundle is present, licensed, and checksummed" do
    %w[manifest.json LICENSE-ASSETS ATTRIBUTION.md VERSION CHECKSUMS].each do |name|
      path = BUNDLE.join(name)
      assert path.file?, "Missing #{name}"
      assert path.size.positive?, "#{name} is empty"
    end

    assert_equal "bryllim/workout-guide", version.fetch("repository")
    assert_equal "v1.0.0", version.fetch("release_tag")
    assert_match(/\A[0-9a-f]{40}\z/, version.fetch("commit_sha"))

    assert BUNDLE.join("LICENSE-ASSETS").dirname.join("assets").directory?
    assert BUNDLE.join("ATTRIBUTION.md").dirname.join("assets").directory?
    assert_includes DOCUMENT_PATH.read, "CC BY-SA 4.0"
  end

  test "records satisfy the general catalog invariants" do
    ids = []
    slugs = []

    records.each do |record|
      assert_equal RECORD_KEYS, record.keys.sort, record["slug"]
      assert_predicate record.fetch("id"), :present?
      assert_predicate record.fetch("slug"), :present?
      assert_predicate record.fetch("name"), :present?
      ids << record.fetch("id")
      slugs << record.fetch("slug")

      frames = record.fetch("frames")
      assert_predicate frames, :present?, record.fetch("slug")
      assert_equal (1..frames.size).to_a, frames.map { |frame| frame.fetch("index") }, record.fetch("slug")

      frames.each do |frame|
        path = frame.fetch("path")
        assert_no_match(%r{(^|/)\.\.(/|$)}, path, path)
        refute Pathname.new(path).absolute?, path
        resolved = BUNDLE.join(path)
        assert resolved.to_s.start_with?("#{BUNDLE}/"), path
        assert resolved.file?, path
        assert resolved.size.positive?, path
      end

      attribution = record.fetch("attribution")
      ATTRIBUTION_KEYS.each { |key| assert_predicate attribution.fetch(key), :present?, record.fetch("slug") }
    end

    assert_equal ids, ids.uniq
    assert_equal slugs, slugs.uniq
  end

  test "the pinned release contains exactly three png frames per record" do
    assert_equal 302, records.size

    referenced = []
    records.each do |record|
      frames = record.fetch("frames")
      assert_equal 3, frames.size, record.fetch("slug")
      frames.each do |frame|
        assert_equal FRAME_KEYS, frame.keys.sort, frame.fetch("path")
        assert_equal "png", frame.fetch("format"), frame.fetch("path")
        assert_equal 512, frame.fetch("width"), frame.fetch("path")
        assert_equal 512, frame.fetch("height"), frame.fetch("path")
        referenced << frame.fetch("path")

        source = frame.fetch("attribution")["source"]
        next unless source

        assert_equal SOURCE_KEYS, source.keys.sort, frame.fetch("path")
        SOURCE_KEYS.each { |key| assert_predicate source.fetch(key), :present?, frame.fetch("path") }
      end
    end

    asset_files = bundle_files.select { |path| path.start_with?("assets/") }
    assert_equal 906, referenced.size
    assert_equal referenced.sort, asset_files
  end

  test "checksums cover every bundle file except CHECKSUMS and match current digests" do
    listed = checksums.keys.sort
    expected = bundle_files - [ "CHECKSUMS" ]
    assert_includes listed, "VERSION"
    assert_equal expected, listed

    checksums.each do |path, digest|
      assert_equal digest, Digest::SHA256.hexdigest(BUNDLE.join(path).binread), path
    end
  end

  test "the vendor bundle contains no svg files or javascript toolchain files" do
    bundle_files.each do |path|
      refute_includes PROHIBITED_NAMES, File.basename(path), path
      path.split("/").each { |part| refute_includes PROHIBITED_DIRECTORIES, part, path }
      refute_includes PROHIBITED_EXTENSIONS, File.extname(path), path
    end
  end

  test "overrides have a closed shape and no duplicate mapping keys" do
    assert_equal OVERRIDE_KEYS, overrides.keys.sort
    assert_equal "workout_guide/v1", overrides.fetch("contract_version")
    assert_equal "bryllim/workout-guide", overrides.dig("source", "repository")
    assert_equal "v1.0.0", overrides.dig("source", "release_tag")
    assert_empty duplicate_mapping_keys(Psych.parse(overrides_text))

    duplicated = overrides_text.sub(
      /^  bench-press:\n(?:    .*\n)+/,
      "\\0  bench-press:\n    modality: strength\n    movement_pattern: horizontal_push\n"
    )
    assert_includes duplicate_mapping_keys(Psych.parse(duplicated)), "bench-press"
  end

  test "every manifest slug has a reviewed modality and movement pattern" do
    exercise_overrides = overrides.fetch("exercises")
    assert_equal records.map { |record| record.fetch("slug") }.sort, exercise_overrides.keys.sort

    exercise_overrides.each do |slug, entry|
      allowed_keys = entry.key?("muscle_targets") ? EXERCISE_KEYS_WITH_TARGETS : EXERCISE_KEYS
      assert_equal allowed_keys, entry.keys.sort, slug
      assert_includes Exercise::MODALITIES, entry.fetch("modality"), slug
      assert_includes Exercise::MOVEMENT_PATTERNS, entry.fetch("movement_pattern"), slug
    end
  end

  test "source muscle names are partitioned into aliases, compounds, and unmapped labels" do
    aliases = overrides.fetch("muscle_aliases")
    compounds = overrides.fetch("muscle_compounds")
    unmapped = overrides.fetch("muscle_unmapped")

    assert_equal UNMAPPED_LABELS, unmapped
    assert_empty aliases.keys & compounds.keys
    assert_empty aliases.keys & unmapped
    assert_empty compounds.keys & unmapped
    assert_equal source_muscle_names, (aliases.keys + compounds.keys + unmapped).sort

    compounds.each do |name, entry|
      assert_equal COMPOUND_KEYS, entry.keys.sort, name
      COMPOUND_KEYS.each do |list_name|
        list = entry.fetch(list_name)
        assert_predicate list, :present?, "#{name}.#{list_name}"
        keys = list.map { |target| assert_target(target, "#{name}.#{list_name}") }
        assert_equal keys, keys.uniq, "#{name}.#{list_name}"
      end
    end
  end

  test "resolved targets keep the strongest role and always include a primary" do
    records.each do |record|
      slug = record.fetch("slug")
      targets = resolved_targets(record)
      keys = targets.map { |target| target.fetch("muscle_key") }
      assert_equal keys, keys.uniq, slug
      assert targets.any? { |target| target.fetch("role") == "primary" }, slug
    end

    sumo = resolved_targets(record_for("sumo-deadlift"))
    glutes = sumo.find { |target| target.fetch("muscle_key") == "glutes" }
    assert_equal "primary", glutes.fetch("role")
  end

  private
    def records
      @records ||= JSON.parse(BUNDLE.join("manifest.json").read)
    end

    def record_for(slug)
      records.find { |record| record.fetch("slug") == slug } || flunk("Missing record: #{slug}")
    end

    def version
      @version ||= BUNDLE.join("VERSION").each_line.to_h { |line|
        key, value = line.rstrip.split(": ", 2)
        [ key, value ]
      }
    end

    def checksums
      @checksums ||= BUNDLE.join("CHECKSUMS").each_line.to_h { |line|
        digest, path = line.rstrip.split(/[ *]{2}/, 2)
        [ path, digest ]
      }
    end

    def bundle_files
      @bundle_files ||= Dir.glob("**/*", base: BUNDLE).select { |path|
        BUNDLE.join(path).file?
      }.sort
    end

    def overrides_text
      @overrides_text ||= OVERRIDES_PATH.read
    end

    def overrides
      @overrides ||= YAML.safe_load(overrides_text, permitted_classes: [], permitted_symbols: [], aliases: false)
    end

    def source_muscle_names
      names = records.flat_map { |record|
        [ record.fetch("primaryMuscle"), *record.fetch("secondaryMuscles") ]
      }
      names.uniq.sort
    end

    def assert_target(target, context)
      assert_equal TARGET_KEYS, target.keys.sort, context
      assert_predicate target.fetch("muscle_key"), :present?, context
      assert_includes ROLES, target.fetch("role"), context
      target.fetch("muscle_key")
    end

    def duplicate_mapping_keys(node)
      case node
      when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
        node.children.flat_map { |child| duplicate_mapping_keys(child) }
      when Psych::Nodes::Mapping
        keys = node.children.each_slice(2).filter_map { |key, _value|
          key.value if key.respond_to?(:value)
        }
        dups = keys.tally.select { |_key, count| count > 1 }.keys
        dups + node.children.each_slice(2).flat_map { |_key, value| duplicate_mapping_keys(value) }
      else
        []
      end
    end

    def expand_muscle(name, position)
      return [] if overrides.fetch("muscle_unmapped").include?(name)

      aliases = overrides.fetch("muscle_aliases")
      if aliases.key?(name)
        role = position == :primary ? "primary" : "secondary"
        return [ { "muscle_key" => aliases.fetch(name), "role" => role } ]
      end

      compound = overrides.fetch("muscle_compounds").fetch(name) {
        flunk("Unmapped source muscle name: #{name}")
      }
      list_name = position == :primary ? "as_primary" : "as_secondary"
      compound.fetch(list_name).map { |target| target.slice("muscle_key", "role") }
    end

    def merge_by_precedence(targets)
      targets.group_by { |target| target.fetch("muscle_key") }.map { |muscle_key, group|
        strongest = group.min_by { |target| ROLE_RANK.fetch(target.fetch("role")) }
        { "muscle_key" => muscle_key, "role" => strongest.fetch("role") }
      }
    end

    def resolved_targets(record)
      override = overrides.fetch("exercises").fetch(record.fetch("slug"))
      if override.key?("muscle_targets")
        override.fetch("muscle_targets").each { |target| assert_target(target, record.fetch("slug")) }
        keys = override.fetch("muscle_targets").map { |target| target.fetch("muscle_key") }
        assert_equal keys, keys.uniq, record.fetch("slug")
        return override.fetch("muscle_targets")
      end

      targets = expand_muscle(record.fetch("primaryMuscle"), :primary)
      record.fetch("secondaryMuscles").each do |name|
        targets.concat(expand_muscle(name, :secondary))
      end
      merge_by_precedence(targets)
    end
end
