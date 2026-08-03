class Agent::RuntimeStatus < ApplicationRecord
  STALE_AFTER = 10.seconds
  STATUSES = %w[ starting online stopped failed ].freeze

  belongs_to :household

  validates :owner, presence: true
  validates :status, inclusion: { in: STATUSES }

  def self.start_all!(owner:, at: Time.current)
    Household.find_each do |household|
      status = find_or_initialize_by(household: household)
      status.assign_attributes(owner: owner, status: "starting", started_at: at,
        heartbeat_at: at, stopped_at: nil, failure_category: nil)
      status.save!
    end
  end

  def self.heartbeat_all!(owner:, at: Time.current)
    Household.find_each do |household|
      status = find_or_initialize_by(household: household)
      status.assign_attributes(owner: owner, status: "online",
        started_at: status.owner == owner ? status.started_at || at : at,
        heartbeat_at: at, stopped_at: nil, failure_category: nil)
      status.save!
    end
  end

  def self.stop_all!(owner:, failed: false, failure_category: nil, at: Time.current)
    where(owner: owner).find_each do |runtime|
      runtime.update!(status: failed ? "failed" : "stopped", stopped_at: at,
        heartbeat_at: at, failure_category: failure_category)
    end
  end

  def online?(at: Time.current)
    status == "online" && heartbeat_at >= at - STALE_AFTER
  end

  def stale?(at: Time.current) = status == "online" && !online?(at: at)

  def state(at: Time.current)
    return "recovering" if stale?(at: at)

    status
  end
end
