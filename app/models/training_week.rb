class TrainingWeek
  Metric = Data.define(:key, :label, :actual, :target, :unit) do
    def configured?
      target.present? && target.positive?
    end

    def remaining
      return unless configured?
      [ target - actual, 0 ].max
    end

    def reached?
      configured? && actual >= target
    end

    def percent
      return unless configured?
      ((actual.to_f / target) * 100).round
    end
  end

  attr_reader :household, :person, :start_date

  class << self
    def current(household:, person:)
      new(household: household, person: person, date: Date.current)
    end

    def for(household:, person:, date:)
      new(household: household, person: person, date: Date.iso8601(date.to_s))
    rescue ArgumentError, Date::Error
      current(household: household, person: person)
    end
  end

  def initialize(household:, person:, date:)
    @household = household
    @person = person
    @start_date = date.beginning_of_week(:monday)
  end

  def end_date
    start_date + 6.days
  end

  def date_range
    start_date..end_date
  end

  def completed_sessions
    @completed_sessions ||= person.training_sessions
      .completed
      .during(date_range)
      .includes(training_session_blocks: { training_session_exercises: :training_sets })
      .order(:performed_on, :started_at)
  end

  def draft_sessions
    @draft_sessions ||= person.training_sessions
      .draft
      .during(date_range)
      .includes(training_session_blocks: { training_session_exercises: :training_sets })
      .order(:performed_on, :started_at)
  end

  def metrics
    @metrics ||= [
      Metric.new(
        key: :structured_minutes,
        label: "Structured minutes",
        actual: structured_minutes,
        target: person.weekly_structured_minutes_target,
        unit: "min"
      ),
      Metric.new(
        key: :strength_sessions,
        label: "Strength sessions",
        actual: strength_sessions,
        target: person.weekly_strength_sessions_target,
        unit: "sessions"
      ),
      Metric.new(
        key: :zone2_minutes,
        label: "Zone 2 minutes",
        actual: classified_minutes("zone2"),
        target: person.weekly_zone2_minutes_target,
        unit: "min"
      ),
      Metric.new(
        key: :vigorous_minutes,
        label: "Vigorous minutes",
        actual: classified_minutes("vigorous"),
        target: person.weekly_vigorous_minutes_target,
        unit: "min"
      )
    ]
  end

  def previous_date
    start_date - 7.days
  end

  def next_date
    start_date + 7.days
  end

  def to_param
    start_date.iso8601
  end

  private
    def structured_minutes
      seconds = completed_sessions.sum do |session|
        session.training_session_blocks.sum { |block| block.actual_duration_seconds.to_i }
      end
      seconds / 60.0
    end

    def strength_sessions
      completed_sessions.count do |session|
        session.training_session_blocks.any? do |block|
          block.training_session_exercises.any? do |exercise|
            exercise.training_sets.any? { |set| set.completed? && set.dose_class == "strength" }
          end
        end
      end
    end

    def classified_minutes(dose_class)
      seconds = completed_sessions.sum do |session|
        session.training_session_blocks.sum do |block|
          block.training_session_exercises.sum do |exercise|
            exercise.training_sets.sum do |set|
              set.completed? && set.dose_class == dose_class ? set.duration_seconds.to_i : 0
            end
          end
        end
      end
      seconds / 60.0
    end
end
