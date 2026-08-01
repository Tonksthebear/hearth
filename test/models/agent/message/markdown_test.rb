require "test_helper"

class Agent::Message::MarkdownTest < ActiveSupport::TestCase
  test "renders CommonMark and strips raw HTML and unsafe links" do
    html = Agent::Message::Markdown.new("**Safe** <script>alert(1)</script> [bad](javascript:alert(2)) [good](https://example.com)").to_html

    assert_includes html, "<strong>Safe</strong>"
    assert_not_includes html, "<script"
    assert_not_includes html, "javascript:"
    assert_includes html, 'href="https://example.com"'
  end
end
