class WorkoutGuide::ImportRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze
  ACTIVE_STATUSES = %w[queued running].freeze
  SAFE_FAILURE_MESSAGE = "The import could not be completed."
  SAFE_ENQUEUE_FAILURE_MESSAGE = "The import could not be queued."
  ACTIVE_REFUSAL_REASON = "import_run_active"

  StartResult = Data.define(:run, :refused) do
    def refused? = refused
  end

  belongs_to :household

  validates :status, inclusion: { in: STATUSES }

  after_commit :broadcast_import, if: :saved_change_to_status?

  class << self
    def active_for(household)
      where(household:, status: ACTIVE_STATUSES).order(:created_at).first
    end

    def latest_for(household)
      where(household:).order(created_at: :desc).first
    end

    def active?(household)
      exists?(household:, status: ACTIVE_STATUSES)
    end

    def action_label(household)
      if household.exercises.from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE).exists?
        "Check for updates"
      else
        "Import Workout Guide"
      end
    end

    def active_refusal?(result)
      result.respond_to?(:reasons) && Array(result.reasons).include?(ACTIVE_REFUSAL_REASON)
    end

    def start!(household:)
      household.with_lock do
        existing = active_for(household)
        return StartResult.new(run: existing, refused: true) if existing

        run = create!(household:, status: "queued")
        begin
          WorkoutGuide::ImportJob.perform_later(run.id)
        rescue StandardError
          run.mark_failed!(SAFE_ENQUEUE_FAILURE_MESSAGE)
          return StartResult.new(run:, refused: true)
        end

        StartResult.new(run:, refused: false)
      end
    rescue ActiveRecord::RecordNotUnique
      StartResult.new(run: active_for(household), refused: true)
    end
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def queue_age
    Time.current - created_at
  end

  def perform!
    update!(status: "running", started_at: Time.current)
    report = WorkoutGuide::Import.new(household: household).run
    update!(
      status: "completed",
      finished_at: Time.current,
      counts: report.counts,
      skipped: report.skipped,
      failures: report.failure_summaries,
      details: report.details
    )
  rescue StandardError
    mark_failed!(SAFE_FAILURE_MESSAGE)
  end

  def mark_failed!(message)
    update!(
      status: "failed",
      finished_at: Time.current,
      failures: [ { "message" => message } ]
    )
    self
  end

  private
    def broadcast_import
      broadcast_replace_to household,
        target: "workout_guide_import",
        partial: "workout_guide_imports/import",
        locals: {
          import_run: self,
          import_action_label: self.class.action_label(household),
          catalog_import_available: !active?
        }
    end
end
