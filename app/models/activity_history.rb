class ActivityHistory
  WINDOW_DAYS = 90

  Item = Data.define(:kind, :record, :title, :description, :status, :occurred_on, :destination)

  attr_reader :household, :person, :start_date, :end_date, :items, :groups

  def initialize(household:, person:, before: nil)
    @household = household
    @person = household.people.find(person.id)
    @end_date = parse_date(before) || Date.current
    @start_date = end_date - (WINDOW_DAYS - 1).days
    @items = load_items.sort_by { |item| [ item.occurred_on, item.record.created_at ] }.reverse.freeze
    @groups = @items.group_by(&:occurred_on).freeze
  end

  def previous_end_date
    start_date - 1.day
  end

  def recent?
    end_date == Date.current
  end

  private
    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue ArgumentError, Date::Error
      nil
    end

    def load_items
      completed_sessions + check_ins + skipped_plans
    end

    def completed_sessions
      person.training_sessions.completed.where(performed_on: start_date..end_date).order(performed_on: :desc, completed_at: :desc).map do |session|
        Item.new(
          kind: :workout,
          record: session,
          title: session.snapshot_title,
          description: "Workout completed",
          status: :completed,
          occurred_on: session.performed_on,
          destination: session
        )
      end
    end

    def check_ins
      person.habit_check_ins
        .where(checked_on: start_date..end_date)
        .includes(person_habit: :habit)
        .order(checked_on: :desc, created_at: :desc)
        .map do |check_in|
          Item.new(
            kind: :habit,
            record: check_in,
            title: check_in.person_habit.habit.name,
            description: "Habit checked off",
            status: :completed,
            occurred_on: check_in.checked_on,
            destination: nil
          )
        end
    end

    def skipped_plans
      person.planned_workouts
        .skipped
        .where(scheduled_on: start_date..end_date)
        .includes(:workout_template)
        .order(scheduled_on: :desc, skipped_at: :desc)
        .map do |plan|
          Item.new(
            kind: :workout,
            record: plan,
            title: plan.workout_template.title,
            description: plan.skip_reason.presence || "Workout skipped",
            status: :skipped,
            occurred_on: plan.scheduled_on,
            destination: plan.workout_template
          )
        end
    end
end
