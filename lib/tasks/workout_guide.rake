namespace :workout_guide do
  desc "Import Workout Guide exercises for one household"
  task :import, [ :household_id ] => :environment do |_task, args|
    household_id = args[:household_id].presence
    abort "Usage: bin/rails \"workout_guide:import[household_id]\"" if household_id.blank?

    household = Household.find_by(id: household_id)
    abort "Unknown household: #{household_id}" if household.nil?

    report = WorkoutGuide::Import.new(household:).run
    report.counts.each do |status, count|
      puts "#{status}: #{count}"
    end
    report.failures.each do |result|
      puts "failed: #{result.reasons.join("; ")}"
    end
  end
end
