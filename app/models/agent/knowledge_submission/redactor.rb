class Agent::KnowledgeSubmission::Redactor
  MAX_CONTENT_BYTES = 65_536
  MAX_PREVIEW_BYTES = 500

  def initialize(household:, person:)
    @household = household
    @person = person
  end

  def redact(value)
    text = value.to_s.dup
    sensitive_values.each do |sensitive|
      text.gsub!(/#{Regexp.escape(sensitive)}/i, "[redacted]")
    end
    bound(text, MAX_CONTENT_BYTES)
  end

  def preview(value) = bound(value, MAX_PREVIEW_BYTES)

  private
    attr_reader :household, :person

    def sensitive_values
      [ household.name, person.name, person.user&.email_address ].compact_blank.uniq.sort_by { |value| -value.bytesize }
    end

    def bound(value, maximum_bytes)
      text = value.to_s
      return text if text.bytesize <= maximum_bytes

      end_index = maximum_bytes
      end_index -= 1 until text.byteslice(0, end_index).valid_encoding?
      text.byteslice(0, end_index)
    end
end
