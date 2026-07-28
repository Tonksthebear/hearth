class Current < ActiveSupport::CurrentAttributes
  attribute :session, :household, :person
  delegate :user, to: :session, allow_nil: true
end
