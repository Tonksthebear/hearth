require "application_system_test_case"

class AgentConversationsTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  test "server rendered chat submits and reconstructs persisted projections" do
    sign_in_via_browser users(:two)

    with_stubbed_method(Acp::Supervisor, :new, ->(*) { raise "Puma must not construct Acp::Supervisor" }) do
      click_link_and_wait_for_path "Coach", agent_conversations_path
      click_link_and_wait_for_path agent_conversations(:active).title, agent_conversation_path(agent_conversations(:active))
      assert_text "Health information, not medical advice"
      assert_no_selector "#agent_messages[aria-live]", visible: :all
      assert_selector "#agent_turn_status[role='status'][aria-live='polite']", text: "Ready"
      assert_selector "main h1", text: agent_conversations(:active).title
      assert_selector "section[aria-labelledby='conversation-heading']"
      assert_selector "aside[aria-label='Agent activity and sources']"

      fill_in_and_wait_for_value "Message the coach", "Summarize my recorded week"
      click_button "Send"
      assert_text "Summarize my recorded week", wait: 5
      assert_text "Pending", wait: 5
    end

    turn = Agent::Turn.order(:id).last
    connect_turbo_cable_stream_sources
    composer = find_field("Message the coach")
    composer.click
    focused_id = page.evaluate_script("document.activeElement.id")
    session = Agent::Session.create!(
      household: turn.household,
      person: turn.person,
      conversation: turn.conversation,
      installation: agent_installations(:local),
      browser_session: turn.browser_session,
      external_session_id: "standard-system-projection",
      status: "connected",
      authentication_status: "authenticated",
      mcp_authorization_status: "authorized"
    )
    turn.attach!(session)
    projection = Agent::Turn::Projection.new(turn)
    projection.apply!(event(session, "agent_message_chunk", {
      "messageId" => "system-answer",
      "content" => { "type" => "text", "text" => "**Persisted answer**" }
    }))
    projection.apply!(event(session, "plan", {
      "entries" => [ { "content" => "Use the persisted record", "status" => "completed" } ]
    }))
    projection.apply!(event(session, "citation", {
      "id" => "system-citation", "title" => "Hearth record", "sourceKind" => "hearth_fact"
    }))
    assert_equal focused_id, page.evaluate_script("document.activeElement.id"), "stream updates must not steal composer focus"

    refresh
    assert_text "Persisted answer", wait: 5
    assert_text "Hearth Fact"
  end

  test "narrow chat transcript contains long streaming content without viewport overflow" do
    sign_in_via_browser users(:two)
    original_size = page.current_window.size
    page.current_window.resize_to(390, 844)
    visit_and_wait_for_path agent_conversation_path(agent_conversations(:active))
    long_token = "long-token-#{'x' * 500}"
    message = agent_conversations(:active).messages.create!(
      household: households(:home), person: people(:two), role: "agent",
      body: "#{long_token}\n\n```text\n#{'y' * 500}\n```", body_digest: Digest::SHA256.hexdigest("#{long_token}\n\n```text\n#{'y' * 500}\n```"),
      source_kind: "agent_suggestion"
    )
    Agent::Citation.create!(
      household: households(:home), person: people(:two), conversation: agent_conversations(:active),
      agent_session: agent_sessions(:connected), external_id: "mobile-citation", title: "citation-#{'z' * 500}",
      source_kind: "external_search"
    )

    refresh
    assert_text message.body.first(40)
    overflow = page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
    overflowers = page.evaluate_script(<<~JAVASCRIPT)
      Array.from(document.querySelectorAll("*")).filter((element) => element.scrollWidth > element.clientWidth + 1).slice(0, 10).map((element) => ({ tag: element.tagName, id: element.id, classes: element.className, client: element.clientWidth, scroll: element.scrollWidth }))
    JAVASCRIPT
    assert_not overflow, "chat content overflowed the narrow viewport: #{overflowers.inspect}"
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.querySelector('##{dom_id(message)} pre')).overflowX")
    assert_selector "label.sr-only", text: "Message the coach", visible: :all
  ensure
    page.current_window.resize_to(original_size[0], original_size[1]) if original_size
  end

  private
    def event(session, kind, attributes)
      {
        "method" => "session/update",
        "params" => {
          "sessionId" => session.external_session_id,
          "update" => attributes.merge("sessionUpdate" => kind)
        }
      }
    end
end
