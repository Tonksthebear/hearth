require "digest"

module Agent::Redactable
  extend ActiveSupport::Concern

  included do
    before_validation :capture_sensitive_body_digests
    validate :redaction_is_terminal, on: :update
  end

  def redact!(by:, reason:)
    raise ArgumentError, "reason is required" if reason.blank?
    return self if redacted_at?

    transaction do
      update!(
        **sensitive_body_columns.index_with { nil },
        redacted_at: Time.current,
        redaction_reason: reason,
        redacted_by: by
      )
      Agent::AuditEvent.record!(
        subject: self,
        event_type: "#{self.class.model_name.element}.redacted",
        actor: by,
        body_digest: sensitive_body_digests.join(":"),
        metadata: { "reason" => reason }
      )
    end
    self
  end

  private
    def capture_sensitive_body_digests
      sensitive_body_columns.each do |column|
        value = public_send(column)
        public_send("#{digest_column_for(column)}=", Digest::SHA256.hexdigest(value)) if value.present?
      end
    end

    def sensitive_body_digests
      sensitive_body_columns.filter_map { |column| public_send(digest_column_for(column)) }
    end

    def digest_column_for(column) = column.to_s.sub(/_body\z/, "") + "_digest"

    def redaction_is_terminal
      return unless attribute_in_database("redacted_at").present?

      protected_columns = [
        *sensitive_body_columns,
        *sensitive_body_columns.map { |column| digest_column_for(column) },
        :redacted_at,
        :redaction_reason,
        :redacted_by_id
      ]
      return unless protected_columns.any? { |column| will_save_change_to_attribute?(column) }

      errors.add(:base, "Redaction cannot be reversed or altered")
    end
end
