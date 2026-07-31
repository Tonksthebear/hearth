class ActivityOverviewsController < ApplicationController
  def show
    @activity_overview = ActivityOverview.current(
      household: Current.household,
      person: Current.person
    )
    paths = {
      training_week: training_week_path,
      recovery_day: recovery_day_path,
      workout_templates: workout_templates_path,
      exercises: exercises_path
    }
    @activity_sections = @activity_overview.sections.map do |section|
      {
        key: section.key,
        title: section.title,
        description: section.description,
        records: section.records,
        path: paths.fetch(section.destination)
      }.freeze
    end.freeze
  end
end
