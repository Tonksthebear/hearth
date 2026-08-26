require "yaml"

class WorkoutGuide::Import
  SOURCE_NAMESPACE = "workout_guide"
  STATUSES = %w[created updated preserved skipped source_removed failed].freeze

  class Error < StandardError; end

  Report = Data.define(:results, :details) do
    def initialize(results:, details: [])
      super(results:, details:)
    end

    def counts
      STATUSES.index_with { |status| results.count { |result| result.status == status } }
    end

    def failures
      results.select { |result| result.status == "failed" }
    end

    def skipped
      details.select { |entry| entry["status"] == "skipped" }
    end

    def failure_summaries
      failures.map { |result| { "message" => result.reasons.join("; ") } }
    end
  end

  def initialize(household:, bundle: WorkoutGuide::Bundle.vendored, overrides_path: WorkoutGuide::MuscleMapping::OVERRIDES_PATH)
    raise ArgumentError, "household is required" if household.nil?

    @household = household
    @bundle = bundle.is_a?(WorkoutGuide::Bundle) ? bundle : WorkoutGuide::Bundle.new(bundle)
    @overrides_path = Pathname(overrides_path)
    @mapping = WorkoutGuide::MuscleMapping.new(path: @overrides_path)
    @overrides = YAML.safe_load(
      @overrides_path.read,
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def run
    require_muscles!

    details = []
    results = @bundle.records.map { |source| import_record(source, details) }
    present_source_keys = @bundle.records.map { |source| source_key_for(source.fetch("slug")) }
    removed = Exercise.mark_sources_removed!(
      household: @household,
      present_source_keys:,
      source_namespace: SOURCE_NAMESPACE
    )
    removed.each { |result| details << detail_for_removed(result) }
    Report.new(results: results + removed, details:)
  end

  def record_for(source_key)
    require_muscles!
    source = @bundle.records.find { |record| source_key_for(record.fetch("slug")) == source_key }
    raise Error, "Unknown catalog record: #{source_key}" if source.nil?

    mapped_record(source)
  end

  def catalog_listing
    linked = @household.exercises.where.not(source_key: nil).pluck(:source_key).to_set
    @bundle.records.filter_map { |source|
      key = source_key_for(source.fetch("slug"))
      next if linked.include?(key)

      { source_key: key, name: source.fetch("name") }
    }
  end

  private
    def require_muscles!
      missing = Muscle::KEYS - Muscle.pluck(:key)
      return if missing.empty?

      raise Error, "Required muscle rows are missing (#{missing.sort.join(", ")}). Run bin/rails db:seed."
    end

    def import_record(source, details)
      slug = source.fetch("slug")
      record = mapped_record(source)
      result = Exercise.merge_source_record!(household: @household, record:)
      details << detail_for(source, result)
      result
    rescue WorkoutGuide::Bundle::Error, ArgumentError, KeyError, TypeError => error
      result = Exercise::SourceMerge::Result.new(
        status: "failed",
        exercise: nil,
        reasons: [ "#{slug}: #{error.message}" ],
        changes: []
      )
      details << detail_for(source, result)
      result
    end

    def detail_for(source, result)
      entry = {
        "source_key" => source_key_for(source.fetch("slug")),
        "name" => source.fetch("name"),
        "status" => result.status,
        "changes" => Array(result.changes),
        "preserved" => Array(result.preserved),
        "reasons" => Array(result.reasons)
      }
      if result.status == "skipped"
        entry["colliding_name"] = @household.exercises.find_by(name: source.fetch("name"))&.name
      end
      entry
    end

    def detail_for_removed(result)
      {
        "source_key" => result.exercise&.source_key,
        "name" => result.exercise&.name,
        "status" => result.status,
        "changes" => Array(result.changes),
        "preserved" => Array(result.preserved),
        "reasons" => Array(result.reasons)
      }
    end

    def mapped_record(source)
      slug = source.fetch("slug")
      pairs = @mapping.targets_for(
        slug:,
        primary_muscle: source.fetch("primaryMuscle"),
        secondary_muscles: source.fetch("secondaryMuscles")
      )
      raise ArgumentError, "Resolved targets are empty" if pairs.empty?
      raise ArgumentError, "Resolved targets must include a primary role" unless pairs.any? { |pair| pair.fetch(:role) == "primary" }

      classification = @overrides.fetch("exercises").fetch(slug)
      {
        source_key: source_key_for(slug),
        source_version: @bundle.release_tag,
        name: source.fetch("name"),
        equipment: source.fetch("equipment"),
        modality: classification.fetch("modality"),
        movement_pattern: classification.fetch("movement_pattern"),
        targets: pairs.to_h { |pair| [ pair.fetch(:muscle).key, pair.fetch(:role) ] },
        visuals: [ visual_for(source) ],
        attribution: attribution_for(source.fetch("attribution"))
      }
    end

    def visual_for(source)
      name = source.fetch("name")
      slug = source.fetch("slug")
      items = Array(source.fetch("frames")).sort_by { |frame| frame.fetch("index") }.map { |frame|
        relative = frame.fetch("path")
        path = @bundle.resolve_asset!(relative)
        {
          source_identifier: relative,
          source_checksum: @bundle.checksum_for!(relative),
          file: Rack::Test::UploadedFile.new(path.to_s, "image/png")
        }
      }

      {
        source_key: "#{SOURCE_NAMESPACE}:#{slug}:frames",
        kind: "frame_sequence",
        alt_text: "#{name} animation frames.",
        caption: nil,
        frame_interval_ms: ExerciseVisual::DEFAULT_FRAME_INTERVAL_MS,
        provenance_status: "verified",
        items:
      }
    end

    def attribution_for(raw)
      data = raw.is_a?(Hash) ? raw : {}
      source = data["source"].is_a?(Hash) ? data["source"] : {}
      {
        "creator" => data["creator"],
        "creator_url" => data["creatorUrl"],
        "license" => data["license"],
        "license_url" => data["licenseUrl"],
        "source_name" => source["name"],
        "source_url" => source["url"],
        "change_note" => source["changes"]
      }
    end

    def source_key_for(slug)
      "#{SOURCE_NAMESPACE}:#{slug}"
    end
end
