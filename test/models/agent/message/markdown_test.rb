require "test_helper"

class Agent::Message::MarkdownTest < ActiveSupport::TestCase
  test "renders CommonMark and strips raw HTML and unsafe links" do
    html = Agent::Message::Markdown.new("**Safe** <script>alert(1)</script> [bad](javascript:alert(2)) [good](https://example.com)").to_html

    assert_includes html, "<strong>Safe</strong>"
    assert_not_includes html, "<script"
    assert_not_includes html, "javascript:"
    assert_includes html, 'href="https://example.com"'
  end

  test "memoizes rendered Markdown by body digest and expires it on redaction" do
    message = agent_messages(:prompt)
    cache = ActiveSupport::Cache::MemoryStore.new
    previous_cache = Rails.cache
    Rails.cache = cache

    first_render = message.rendered_body
    cache.write(message.send(:rendered_body_cache_key), "cached render")

    assert_equal "cached render", message.rendered_body

    message.redact!(by: users(:one), reason: "Operator request")

    assert_nil cache.read([ "agent-message-markdown", 1, message.body_digest ])
    assert_equal "", message.rendered_body.strip
    refute_equal first_render, message.rendered_body
  ensure
    Rails.cache = previous_cache if previous_cache
  end
end
