require "uri"

class Agent::Message::Markdown
  ALLOWED_TAGS = %w[p br strong em del code pre blockquote ul ol li h1 h2 h3 h4 a].freeze
  ALLOWED_ATTRIBUTES = %w[href title].freeze
  SAFE_SCHEMES = %w[http https].freeze

  def initialize(body)
    @body = body.to_s.encode(Encoding::UTF_8)
  end

  def to_html
    html = Commonmarker.to_html(@body, options: {
      render: { unsafe: false },
      extension: { strikethrough: true }
    })
    sanitized = Rails::HTML5::SafeListSanitizer.new.sanitize(
      html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES
    )
    sanitized.gsub(/href="([^"]+)"/) do |attribute|
      safe_url?(Regexp.last_match(1)) ? attribute : ""
    end.html_safe
  end

  private
    def safe_url?(value)
      uri = URI.parse(value)
      uri.scheme.nil? || SAFE_SCHEMES.include?(uri.scheme.downcase)
    rescue URI::InvalidURIError
      false
    end
end
