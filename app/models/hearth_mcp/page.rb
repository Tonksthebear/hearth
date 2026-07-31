require "base64"
require "json"

module HearthMcp
  class Page
    MAX_LIMIT = 50
    DEFAULT_LIMIT = 25

    attr_reader :records, :next_cursor

    def initialize(scope, limit: DEFAULT_LIMIT, cursor: nil)
      limit = Integer(limit || DEFAULT_LIMIT)
      raise ArgumentError, "limit must be between 1 and #{MAX_LIMIT}" unless limit.between?(1, MAX_LIMIT)

      after_id = decode(cursor)
      rows = scope.reorder(:id).where("id > ?", after_id).limit(limit + 1).to_a
      @records = rows.first(limit)
      @next_cursor = encode(@records.last.id) if rows.length > limit
    rescue JSON::ParserError, ArgumentError => error
      raise ArgumentError, error.message.start_with?("limit") ? error.message : "cursor is invalid"
    end

    private
      def encode(id)
        Base64.urlsafe_encode64(JSON.generate({ id: id }), padding: false)
      end

      def decode(cursor)
        return 0 if cursor.blank?

        value = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
        Integer(value.fetch("id"), exception: true).tap { |id| raise ArgumentError if id.negative? }
      end
  end
end
