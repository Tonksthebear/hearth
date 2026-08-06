# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_05_040000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_audit_events", force: :cascade do |t|
    t.integer "actor_id"
    t.integer "agent_session_id"
    t.string "body_digest"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.integer "household_id", null: false
    t.json "metadata", default: {}, null: false
    t.string "outcome"
    t.integer "person_id", null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_agent_audit_events_on_actor_id"
    t.index ["agent_session_id"], name: "index_agent_audit_events_on_agent_session_id"
    t.index ["conversation_id", "created_at"], name: "index_agent_audit_events_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_agent_audit_events_on_conversation_id"
    t.index ["household_id", "person_id", "created_at"], name: "index_agent_audit_events_on_context_and_created_at"
    t.index ["household_id"], name: "index_agent_audit_events_on_household_id"
    t.index ["person_id"], name: "index_agent_audit_events_on_person_id"
    t.index ["subject_type", "subject_id"], name: "index_agent_audit_events_on_subject_type_and_subject_id"
  end

  create_table "agent_citations", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.integer "household_id", null: false
    t.integer "message_id"
    t.integer "person_id", null: false
    t.string "source_kind", default: "external_search", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["agent_session_id", "external_id"], name: "index_agent_citations_on_agent_session_id_and_external_id", unique: true
    t.index ["agent_session_id"], name: "index_agent_citations_on_agent_session_id"
    t.index ["conversation_id", "created_at"], name: "index_agent_citations_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_agent_citations_on_conversation_id"
    t.index ["household_id"], name: "index_agent_citations_on_household_id"
    t.index ["message_id"], name: "index_agent_citations_on_message_id"
    t.index ["person_id"], name: "index_agent_citations_on_person_id"
    t.check_constraint "source_kind IN ('hearth_fact', 'vault_knowledge', 'external_search', 'agent_suggestion')", name: "agent_citations_source_kind"
  end

  create_table "agent_conversations", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.integer "profile_id", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "person_id", "status"], name: "index_agent_conversations_on_context_and_status"
    t.index ["household_id"], name: "index_agent_conversations_on_household_id"
    t.index ["person_id"], name: "index_agent_conversations_on_person_id"
    t.index ["profile_id"], name: "index_agent_conversations_on_profile_id"
    t.check_constraint "status IN ('active', 'closed')", name: "agent_conversations_status"
  end

  create_table "agent_grants", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.integer "browser_session_id"
    t.integer "calls_limit"
    t.integer "calls_used", default: 0, null: false
    t.json "capability_groups", default: [], null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "household_id", null: false
    t.integer "issued_by_id"
    t.integer "output_tokens_limit"
    t.integer "output_tokens_used", default: 0, null: false
    t.integer "person_id", null: false
    t.text "revocation_reason"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_locator", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_session_id"], name: "index_agent_grants_on_agent_session_id"
    t.index ["browser_session_id", "revoked_at"], name: "index_agent_grants_on_browser_session_id_and_revoked_at"
    t.index ["browser_session_id"], name: "index_agent_grants_on_browser_session_id"
    t.index ["conversation_id"], name: "index_agent_grants_on_conversation_id"
    t.index ["household_id"], name: "index_agent_grants_on_household_id"
    t.index ["issued_by_id"], name: "index_agent_grants_on_issued_by_id"
    t.index ["person_id"], name: "index_agent_grants_on_person_id"
    t.index ["token_locator"], name: "index_agent_grants_on_token_locator", unique: true
    t.check_constraint "calls_limit IS NULL OR calls_limit >= 0", name: "agent_grants_nonnegative_calls_limit"
    t.check_constraint "calls_used >= 0", name: "agent_grants_nonnegative_calls_used"
    t.check_constraint "output_tokens_limit IS NULL OR output_tokens_limit >= 0", name: "agent_grants_nonnegative_output_tokens_limit"
    t.check_constraint "output_tokens_used >= 0", name: "agent_grants_nonnegative_output_tokens_used"
  end

  create_table "agent_installations", force: :cascade do |t|
    t.json "advertised_capabilities", default: {}, null: false
    t.string "agent_version"
    t.datetime "authentication_approved_at"
    t.string "authentication_method_id"
    t.json "authentication_methods", default: [], null: false
    t.string "authentication_origin"
    t.string "authentication_status", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.string "executable_path", null: false
    t.string "external_id", null: false
    t.integer "household_id", null: false
    t.datetime "last_seen_at"
    t.integer "profile_id", null: false
    t.integer "protocol_version", null: false
    t.string "status", default: "observed", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "external_id"], name: "index_agent_installations_on_household_id_and_external_id", unique: true
    t.index ["household_id"], name: "index_agent_installations_on_household_id"
    t.index ["profile_id"], name: "index_agent_installations_on_profile_id"
    t.check_constraint "authentication_status IN ('unknown', 'not_required', 'required', 'authenticated', 'failed')", name: "agent_installations_authentication_status"
    t.check_constraint "protocol_version > 0", name: "agent_installations_positive_protocol"
    t.check_constraint "status IN ('observed', 'available', 'unavailable')", name: "agent_installations_status"
  end

  create_table "agent_knowledge_submissions", force: :cascade do |t|
    t.integer "agent_grant_id", null: false
    t.integer "agent_session_id", null: false
    t.text "content", null: false
    t.string "content_digest", null: false
    t.text "content_preview", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "diagnostic"
    t.datetime "dispatched_at"
    t.integer "household_id", null: false
    t.datetime "last_polled_at"
    t.string "lorester_submission_id"
    t.integer "message_id", null: false
    t.string "origin", null: false
    t.integer "person_id", null: false
    t.json "provenance", default: {}, null: false
    t.string "request_id", null: false
    t.string "requested_intent", null: false
    t.string "status", default: "pending", null: false
    t.datetime "terminal_at"
    t.datetime "updated_at", null: false
    t.index ["agent_grant_id"], name: "index_agent_knowledge_submissions_on_agent_grant_id"
    t.index ["agent_session_id", "request_id"], name: "index_agent_knowledge_submissions_on_session_and_request", unique: true
    t.index ["agent_session_id"], name: "index_agent_knowledge_submissions_on_agent_session_id"
    t.index ["conversation_id"], name: "index_agent_knowledge_submissions_on_conversation_id"
    t.index ["household_id"], name: "index_agent_knowledge_submissions_on_household_id"
    t.index ["lorester_submission_id"], name: "index_agent_knowledge_submissions_on_lorester_submission_id", unique: true, where: "lorester_submission_id IS NOT NULL"
    t.index ["message_id"], name: "index_agent_knowledge_submissions_on_message_id"
    t.index ["person_id"], name: "index_agent_knowledge_submissions_on_person_id"
    t.check_constraint "status IN ('pending', 'accepted', 'materialized', 'admitted', 'processing', 'complete', 'failed', 'unavailable')", name: "agent_knowledge_submissions_status"
  end

  create_table "agent_messages", force: :cascade do |t|
    t.integer "agent_session_id"
    t.text "body"
    t.string "body_digest", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "external_id"
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.json "provenance", default: {}, null: false
    t.datetime "redacted_at"
    t.integer "redacted_by_id"
    t.text "redaction_reason"
    t.string "role", null: false
    t.string "source_kind", default: "hearth_fact", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_session_id", "external_id"], name: "index_agent_messages_on_session_and_external_id", unique: true, where: "external_id IS NOT NULL"
    t.index ["agent_session_id"], name: "index_agent_messages_on_agent_session_id"
    t.index ["conversation_id", "created_at"], name: "index_agent_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_agent_messages_on_conversation_id"
    t.index ["household_id"], name: "index_agent_messages_on_household_id"
    t.index ["person_id"], name: "index_agent_messages_on_person_id"
    t.index ["redacted_by_id"], name: "index_agent_messages_on_redacted_by_id"
    t.check_constraint "(body IS NOT NULL AND redacted_at IS NULL) OR (body IS NULL AND redacted_at IS NOT NULL)", name: "agent_messages_redaction_state"
    t.check_constraint "role IN ('user', 'agent', 'system')", name: "agent_messages_role"
    t.check_constraint "source_kind IN ('hearth_fact', 'vault_knowledge', 'external_search', 'agent_suggestion')", name: "agent_messages_source_kind"
  end

  create_table "agent_mutation_executions", force: :cascade do |t|
    t.json "after_state", default: {}, null: false
    t.json "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "executed_at", null: false
    t.integer "executed_by_id"
    t.string "idempotency_key", null: false
    t.string "input_digest", null: false
    t.integer "mutation_proposal_id", null: false
    t.string "operation", null: false
    t.string "outcome", null: false
    t.json "result", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["executed_by_id"], name: "index_agent_mutation_executions_on_executed_by_id"
    t.index ["mutation_proposal_id"], name: "index_agent_mutation_executions_on_mutation_proposal_id", unique: true
    t.check_constraint "outcome = 'succeeded'", name: "agent_mutation_executions_outcome"
  end

  create_table "agent_mutation_proposals", force: :cascade do |t|
    t.integer "agent_grant_id", null: false
    t.integer "agent_session_id", null: false
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.string "confirmation_digest", null: false
    t.string "confirmation_nonce", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deadline_at", null: false
    t.datetime "executed_at"
    t.integer "executed_by_id"
    t.string "expected_state_digest", null: false
    t.text "failure_reason"
    t.integer "household_id", null: false
    t.string "idempotency_key", null: false
    t.text "input_body", null: false
    t.string "input_digest", null: false
    t.string "operation", null: false
    t.integer "person_id", null: false
    t.json "preview", default: {}, null: false
    t.integer "requested_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "terminal_at"
    t.datetime "updated_at", null: false
    t.index ["agent_grant_id"], name: "index_agent_mutation_proposals_on_agent_grant_id"
    t.index ["agent_session_id", "idempotency_key"], name: "index_agent_mutation_proposals_on_session_and_idempotency", unique: true
    t.index ["agent_session_id"], name: "index_agent_mutation_proposals_on_agent_session_id"
    t.index ["approved_by_id"], name: "index_agent_mutation_proposals_on_approved_by_id"
    t.index ["confirmation_digest"], name: "index_agent_mutation_proposals_on_confirmation_digest", unique: true
    t.index ["confirmation_nonce"], name: "index_agent_mutation_proposals_on_confirmation_nonce", unique: true
    t.index ["conversation_id", "status"], name: "index_agent_mutation_proposals_on_conversation_and_status"
    t.index ["conversation_id"], name: "index_agent_mutation_proposals_on_conversation_id"
    t.index ["executed_by_id"], name: "index_agent_mutation_proposals_on_executed_by_id"
    t.index ["household_id"], name: "index_agent_mutation_proposals_on_household_id"
    t.index ["person_id"], name: "index_agent_mutation_proposals_on_person_id"
    t.index ["requested_by_id"], name: "index_agent_mutation_proposals_on_requested_by_id"
    t.check_constraint "status IN ('pending', 'approved', 'denied', 'cancelled', 'expired', 'executed', 'failed')", name: "agent_mutation_proposals_status"
  end

  create_table "agent_operational_authorizations", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.datetime "authorized_at", null: false
    t.integer "authorized_by_id", null: false
    t.integer "browser_session_id"
    t.json "capability_groups", default: ["health_write"], null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.text "reason", null: false
    t.integer "revision", default: 1, null: false
    t.text "revocation_reason"
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.index ["agent_session_id", "revoked_at"], name: "index_agent_operational_authorizations_on_session_and_active"
    t.index ["agent_session_id"], name: "index_agent_operational_authorizations_on_agent_session_id"
    t.index ["authorized_by_id"], name: "index_agent_operational_authorizations_on_authorized_by_id"
    t.index ["browser_session_id", "revoked_at"], name: "index_agent_operational_authorizations_on_browser_and_active"
    t.index ["browser_session_id"], name: "index_agent_operational_authorizations_on_browser_session_id"
    t.index ["conversation_id"], name: "index_agent_operational_authorizations_on_conversation_id"
    t.index ["household_id"], name: "index_agent_operational_authorizations_on_household_id"
    t.index ["person_id"], name: "index_agent_operational_authorizations_on_person_id"
    t.check_constraint "revision > 0", name: "agent_operational_authorizations_positive_revision"
  end

  create_table "agent_permission_decisions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "decided_by_id", null: false
    t.string "outcome", null: false
    t.integer "permission_request_id", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["decided_by_id"], name: "index_agent_permission_decisions_on_decided_by_id"
    t.index ["permission_request_id"], name: "index_agent_permission_decisions_on_permission_request_id", unique: true
    t.check_constraint "outcome IN ('approved', 'denied')", name: "agent_permission_decisions_outcome"
  end

  create_table "agent_permission_requests", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.string "capability", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deadline_at"
    t.string "external_request_id", null: false
    t.integer "household_id", null: false
    t.text "input_body"
    t.string "input_digest", null: false
    t.integer "permission_subject_id"
    t.string "permission_subject_type"
    t.integer "person_id", null: false
    t.datetime "redacted_at"
    t.integer "redacted_by_id"
    t.text "redaction_reason"
    t.string "status", default: "pending", null: false
    t.datetime "terminal_at"
    t.string "tool_name", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_session_id", "external_request_id"], name: "index_agent_permission_requests_on_session_and_external_id", unique: true
    t.index ["agent_session_id"], name: "index_agent_permission_requests_on_agent_session_id"
    t.index ["conversation_id", "status"], name: "index_agent_permission_requests_on_conversation_id_and_status"
    t.index ["conversation_id"], name: "index_agent_permission_requests_on_conversation_id"
    t.index ["household_id"], name: "index_agent_permission_requests_on_household_id"
    t.index ["permission_subject_type", "permission_subject_id"], name: "index_agent_permission_requests_on_permission_subject", unique: true
    t.index ["person_id"], name: "index_agent_permission_requests_on_person_id"
    t.index ["redacted_by_id"], name: "index_agent_permission_requests_on_redacted_by_id"
    t.check_constraint "(input_body IS NOT NULL AND redacted_at IS NULL) OR (input_body IS NULL AND redacted_at IS NOT NULL)", name: "agent_permission_requests_redaction_state"
    t.check_constraint "(permission_subject_type IS NULL AND permission_subject_id IS NULL) OR (permission_subject_type IN ('Agent::MutationProposal', 'Agent::KnowledgeSubmission') AND permission_subject_id IS NOT NULL)", name: "agent_permission_requests_known_subject"
    t.check_constraint "status IN ('pending', 'approved', 'denied', 'cancelled', 'expired')", name: "agent_permission_requests_status"
  end

  create_table "agent_plans", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.json "entries", default: [], null: false
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_session_id"], name: "index_agent_plans_on_agent_session_id"
    t.index ["conversation_id"], name: "index_agent_plans_on_conversation_id", unique: true
    t.index ["household_id"], name: "index_agent_plans_on_household_id"
    t.index ["person_id"], name: "index_agent_plans_on_person_id"
  end

  create_table "agent_profiles", force: :cascade do |t|
    t.json "arguments", default: [], null: false
    t.string "certified_key"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.json "environment_keys", default: [], null: false
    t.text "executable_path", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "update_policy", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.string "working_directory"
    t.index ["household_id", "certified_key"], name: "index_agent_profiles_on_household_and_certified_key", unique: true, where: "certified_key IS NOT NULL"
    t.index ["household_id", "name"], name: "index_agent_profiles_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_agent_profiles_on_household_id"
    t.check_constraint "update_policy = 'manual'", name: "agent_profiles_manual_update_policy"
  end

  create_table "agent_runtime_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "failure_category"
    t.datetime "heartbeat_at", null: false
    t.integer "household_id", null: false
    t.string "owner", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "online", null: false
    t.datetime "stopped_at"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_agent_runtime_statuses_on_household_id", unique: true
    t.check_constraint "status IN ('starting', 'online', 'stopped', 'failed')", name: "agent_runtime_statuses_status"
  end

  create_table "agent_sessions", force: :cascade do |t|
    t.json "advertised_capabilities", default: {}, null: false
    t.string "authentication_status", default: "unknown", null: false
    t.integer "browser_session_id"
    t.datetime "closed_at"
    t.datetime "connected_at"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "disconnected_at"
    t.string "external_session_id"
    t.integer "household_id", null: false
    t.integer "installation_id", null: false
    t.string "mcp_authorization_status", default: "not_configured", null: false
    t.integer "person_id", null: false
    t.integer "recovery_attempts", default: 0, null: false
    t.string "recovery_error"
    t.datetime "recovery_next_at"
    t.string "status", default: "starting", null: false
    t.datetime "updated_at", null: false
    t.index ["browser_session_id"], name: "index_agent_sessions_on_browser_session_id"
    t.index ["conversation_id", "status"], name: "index_agent_sessions_on_conversation_id_and_status"
    t.index ["conversation_id"], name: "index_agent_sessions_on_conversation_id"
    t.index ["household_id"], name: "index_agent_sessions_on_household_id"
    t.index ["installation_id", "external_session_id"], name: "index_agent_sessions_on_installation_and_external_id", unique: true
    t.index ["installation_id"], name: "index_agent_sessions_on_installation_id"
    t.index ["person_id"], name: "index_agent_sessions_on_person_id"
    t.check_constraint "authentication_status IN ('unknown', 'not_required', 'required', 'authenticated', 'failed')", name: "agent_sessions_authentication_status"
    t.check_constraint "mcp_authorization_status IN ('not_configured', 'authorized', 'reauthorization_required')", name: "agent_sessions_mcp_authorization_status"
    t.check_constraint "recovery_attempts >= 0", name: "agent_sessions_nonnegative_recovery_attempts"
    t.check_constraint "status IN ('starting', 'connected', 'disconnected', 'closed', 'failed')", name: "agent_sessions_status"
  end

  create_table "agent_setup_requests", force: :cascade do |t|
    t.string "action", null: false
    t.boolean "adapter_available"
    t.string "adapter_version"
    t.string "authentication_method_id"
    t.datetime "cancel_requested_at"
    t.string "certified_key", null: false
    t.datetime "claimed_at"
    t.string "claimed_by"
    t.boolean "cli_available"
    t.string "cli_version"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.string "error_category"
    t.string "error_message"
    t.datetime "heartbeat_at"
    t.integer "household_id", null: false
    t.string "idempotency_key", null: false
    t.datetime "lease_expires_at"
    t.string "origin", null: false
    t.integer "requested_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "idempotency_key"], name: "index_agent_setup_requests_on_household_and_idempotency", unique: true
    t.index ["household_id"], name: "index_agent_setup_requests_on_household_id"
    t.index ["requested_by_id"], name: "index_agent_setup_requests_on_requested_by_id"
    t.index ["status", "created_at"], name: "index_agent_setup_requests_on_status_and_created_at"
    t.check_constraint "action IN ('detect', 'enable', 'authenticate', 'reauthenticate', 'disable')", name: "agent_setup_requests_action"
    t.check_constraint "origin IN ('web', 'cli')", name: "agent_setup_requests_origin"
    t.check_constraint "status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled', 'expired')", name: "agent_setup_requests_status"
  end

  create_table "agent_tool_activities", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.string "capability", null: false
    t.datetime "completed_at"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "display_title"
    t.string "external_id"
    t.integer "household_id", null: false
    t.text "input_body"
    t.string "input_digest", null: false
    t.string "kind"
    t.text "output_body"
    t.string "output_digest"
    t.integer "output_tokens"
    t.integer "person_id", null: false
    t.json "provenance", default: {}, null: false
    t.datetime "redacted_at"
    t.integer "redacted_by_id"
    t.text "redaction_reason"
    t.string "source", default: "mcp", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "tool_name"
    t.datetime "updated_at", null: false
    t.index ["agent_session_id", "external_id"], name: "index_agent_tool_activities_on_session_and_external_id", unique: true, where: "external_id IS NOT NULL"
    t.index ["agent_session_id"], name: "index_agent_tool_activities_on_agent_session_id"
    t.index ["conversation_id", "created_at"], name: "index_agent_tool_activities_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_agent_tool_activities_on_conversation_id"
    t.index ["household_id"], name: "index_agent_tool_activities_on_household_id"
    t.index ["person_id"], name: "index_agent_tool_activities_on_person_id"
    t.index ["redacted_by_id"], name: "index_agent_tool_activities_on_redacted_by_id"
    t.check_constraint "(input_body IS NOT NULL AND redacted_at IS NULL) OR (input_body IS NULL AND redacted_at IS NOT NULL)", name: "agent_tool_activities_redaction_state"
    t.check_constraint "(source = 'mcp' AND tool_name IS NOT NULL) OR (source = 'acp' AND display_title IS NOT NULL AND kind IS NOT NULL)", name: "agent_tool_activities_source_shape"
    t.check_constraint "output_tokens IS NULL OR output_tokens >= 0", name: "agent_tool_activities_nonnegative_output_tokens"
    t.check_constraint "source IN ('mcp', 'acp')", name: "agent_tool_activities_source"
    t.check_constraint "status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')", name: "agent_tool_activities_status"
  end

  create_table "agent_turns", force: :cascade do |t|
    t.integer "agent_session_id"
    t.integer "browser_session_id", null: false
    t.datetime "cancel_requested_at"
    t.datetime "cancel_sent_at"
    t.datetime "claimed_at"
    t.string "claimed_by"
    t.datetime "completed_at"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.integer "dropped_event_count", default: 0, null: false
    t.string "error_message"
    t.datetime "heartbeat_at"
    t.integer "household_id", null: false
    t.string "idempotency_key", null: false
    t.datetime "lease_expires_at"
    t.integer "person_id", null: false
    t.string "status", default: "pending", null: false
    t.string "stop_reason"
    t.datetime "updated_at", null: false
    t.integer "user_message_id", null: false
    t.string "warning_message"
    t.index ["agent_session_id"], name: "index_agent_turns_on_agent_session_id"
    t.index ["browser_session_id", "idempotency_key"], name: "index_agent_turns_on_browser_session_id_and_idempotency_key", unique: true
    t.index ["browser_session_id"], name: "index_agent_turns_on_browser_session_id"
    t.index ["conversation_id", "created_at"], name: "index_agent_turns_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_agent_turns_on_conversation_id"
    t.index ["household_id"], name: "index_agent_turns_on_household_id"
    t.index ["person_id"], name: "index_agent_turns_on_person_id"
    t.index ["status", "lease_expires_at"], name: "index_agent_turns_on_status_and_lease_expires_at"
    t.index ["user_message_id"], name: "index_agent_turns_on_user_message_id"
    t.check_constraint "dropped_event_count >= 0", name: "agent_turns_dropped_event_count"
    t.check_constraint "status IN ('pending', 'claimed', 'running', 'succeeded', 'failed', 'cancelled')", name: "agent_turns_status"
  end

  create_table "exercise_prescriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dose_class"
    t.integer "exercise_id", null: false
    t.text "load_guidance"
    t.text "notes"
    t.boolean "per_side", default: false, null: false
    t.string "performance_kind", default: "reps", null: false
    t.integer "position", null: false
    t.integer "rep_max"
    t.integer "rep_min"
    t.integer "rest_seconds"
    t.integer "sets_count", default: 1, null: false
    t.integer "target_count"
    t.string "target_count_unit"
    t.decimal "target_distance_amount", precision: 10, scale: 2
    t.string "target_distance_unit"
    t.integer "target_heart_rate_max"
    t.integer "target_heart_rate_min"
    t.string "target_heart_rate_unit"
    t.decimal "target_rir", precision: 3, scale: 1
    t.decimal "target_rpe", precision: 3, scale: 1
    t.string "tempo_cue"
    t.datetime "updated_at", null: false
    t.integer "work_seconds"
    t.integer "workout_block_id", null: false
    t.index ["exercise_id"], name: "index_exercise_prescriptions_on_exercise_id"
    t.index ["workout_block_id", "position"], name: "index_exercise_prescriptions_on_workout_block_id_and_position", unique: true
    t.index ["workout_block_id"], name: "index_exercise_prescriptions_on_workout_block_id"
    t.check_constraint "dose_class IS NULL OR dose_class IN ('none', 'strength', 'zone2', 'vigorous')", name: "exercise_prescriptions_dose_class"
    t.check_constraint "performance_kind IN ('reps', 'duration', 'distance', 'count', 'interval')", name: "exercise_prescriptions_performance_kind"
    t.check_constraint "position > 0", name: "exercise_prescriptions_positive_position"
    t.check_constraint "sets_count > 0", name: "exercise_prescriptions_positive_sets"
    t.check_constraint "target_count_unit IS NULL OR target_count_unit IN ('laps', 'flights', 'steps')", name: "exercise_prescriptions_target_count_unit"
    t.check_constraint "target_distance_unit IS NULL OR target_distance_unit IN ('m', 'km', 'mi', 'ft')", name: "exercise_prescriptions_target_distance_unit"
    t.check_constraint "target_heart_rate_unit IS NULL OR target_heart_rate_unit IN ('bpm', 'percent_max')", name: "exercise_prescriptions_target_heart_rate_unit"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "equipment"
    t.text "guidance"
    t.integer "household_id", null: false
    t.string "modality", null: false
    t.string "movement_pattern", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_exercises_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_exercises_on_household_id"
    t.check_constraint "modality IN ('strength', 'cardio', 'mobility', 'balance', 'recovery', 'mixed', 'other')", name: "exercises_modality"
    t.check_constraint "movement_pattern IN ('squat', 'hinge', 'lunge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull', 'carry', 'core', 'locomotion_cardio', 'mobility', 'balance', 'other')", name: "exercises_movement_pattern"
  end

  create_table "habit_check_in_measurements", force: :cascade do |t|
    t.boolean "boolean_value"
    t.datetime "created_at", null: false
    t.integer "duration_value"
    t.integer "habit_check_in_id", null: false
    t.integer "habit_metric_id", null: false
    t.decimal "number_value", precision: 12, scale: 3
    t.time "time_of_day_value"
    t.datetime "updated_at", null: false
    t.index ["habit_check_in_id", "habit_metric_id"], name: "index_habit_measurements_on_check_in_and_metric", unique: true
    t.index ["habit_check_in_id"], name: "index_habit_check_in_measurements_on_habit_check_in_id"
    t.index ["habit_metric_id"], name: "index_habit_check_in_measurements_on_habit_metric_id"
    t.check_constraint "(CASE WHEN habit_check_in_measurements.number_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN habit_check_in_measurements.duration_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN habit_check_in_measurements.time_of_day_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN habit_check_in_measurements.boolean_value IS NULL THEN 0 ELSE 1 END) = 1", name: "habit_measurements_one_typed_value"
    t.check_constraint "duration_value IS NULL OR duration_value >= 0", name: "habit_measurements_nonnegative_duration"
  end

  create_table "habit_check_ins", force: :cascade do |t|
    t.date "checked_on", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "person_habit_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_habit_id", "checked_on"], name: "index_habit_check_ins_on_person_habit_id_and_checked_on", unique: true
    t.index ["person_habit_id"], name: "index_habit_check_ins_on_person_habit_id"
  end

  create_table "habit_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "habit_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.integer "position", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.string "value_type", null: false
    t.index ["habit_id", "key"], name: "index_habit_metrics_on_habit_id_and_key", unique: true
    t.index ["habit_id", "position"], name: "index_habit_metrics_on_habit_id_and_position", unique: true
    t.index ["habit_id"], name: "index_habit_metrics_on_habit_id"
    t.check_constraint "position > 0", name: "habit_metrics_positive_position"
    t.check_constraint "value_type IN ('number', 'duration', 'time_of_day', 'boolean')", name: "habit_metrics_value_type"
  end

  create_table "habits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_habits_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_habits_on_household_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "installation_key", default: 1, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_key"], name: "index_households_on_installation_key", unique: true
    t.check_constraint "installation_key = 1", name: "households_single_installation"
  end

  create_table "ingredient_nutrient_values", force: :cascade do |t|
    t.decimal "amount_per_100_grams", precision: 14, scale: 6, null: false
    t.datetime "created_at", null: false
    t.integer "ingredient_id", null: false
    t.integer "nutrient_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id", "nutrient_id"], name: "idx_on_ingredient_id_nutrient_id_3bd58c685a", unique: true
    t.index ["ingredient_id"], name: "index_ingredient_nutrient_values_on_ingredient_id"
    t.index ["nutrient_id"], name: "index_ingredient_nutrient_values_on_nutrient_id"
    t.check_constraint "amount_per_100_grams >= 0", name: "ingredient_nutrient_values_nonnegative_amount"
  end

  create_table "ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "food_data_central_id"
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "nutrition_provenance_status"
    t.string "nutrition_source_name"
    t.datetime "updated_at", null: false
    t.index ["household_id", "normalized_name"], name: "index_ingredients_on_household_id_and_normalized_name", unique: true
    t.index ["household_id"], name: "index_ingredients_on_household_id"
    t.check_constraint "nutrition_provenance_status IS NULL OR nutrition_provenance_status IN ('personal', 'verified', 'adapted', 'observed')", name: "ingredients_nutrition_provenance_status"
  end

  create_table "meal_item_nutrient_values", force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 6, null: false
    t.datetime "created_at", null: false
    t.integer "meal_item_id", null: false
    t.integer "nutrient_id"
    t.string "snapshot_calculation_kind", null: false
    t.string "snapshot_key", null: false
    t.string "snapshot_name", null: false
    t.string "snapshot_provenance_status"
    t.string "snapshot_source_name"
    t.string "snapshot_unit", null: false
    t.datetime "updated_at", null: false
    t.index ["meal_item_id", "snapshot_key"], name: "index_meal_item_nutrients_on_item_and_snapshot_key", unique: true
    t.index ["meal_item_id"], name: "index_meal_item_nutrient_values_on_meal_item_id"
    t.index ["nutrient_id"], name: "index_meal_item_nutrient_values_on_nutrient_id"
    t.check_constraint "amount >= 0", name: "meal_item_nutrient_values_nonnegative_amount"
    t.check_constraint "snapshot_calculation_kind IN ('explicit', 'estimated')", name: "meal_item_nutrient_values_calculation_kind"
  end

  create_table "meal_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "ingredient_id"
    t.integer "meal_id", null: false
    t.text "notes"
    t.boolean "nutrition_complete", default: false, null: false
    t.boolean "nutrition_estimated", default: false, null: false
    t.decimal "portion_amount", precision: 10, scale: 3
    t.string "portion_unit"
    t.integer "position", null: false
    t.integer "recipe_id"
    t.string "snapshot_label", null: false
    t.string "source_kind", null: false
    t.text "substitutions"
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_meal_items_on_ingredient_id"
    t.index ["meal_id", "position"], name: "index_meal_items_on_meal_id_and_position", unique: true
    t.index ["meal_id"], name: "index_meal_items_on_meal_id"
    t.index ["recipe_id"], name: "index_meal_items_on_recipe_id"
    t.check_constraint "(source_kind = 'recipe' AND recipe_id IS NOT NULL AND ingredient_id IS NULL) OR (source_kind = 'ingredient' AND recipe_id IS NULL AND ingredient_id IS NOT NULL) OR (source_kind = 'free_text' AND recipe_id IS NULL AND ingredient_id IS NULL)", name: "meal_items_exactly_one_source"
    t.check_constraint "portion_amount IS NULL OR portion_amount > 0", name: "meal_items_positive_portion_amount"
    t.check_constraint "position > 0", name: "meal_items_positive_position"
  end

  create_table "meals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "eaten_at"
    t.date "eaten_on", null: false
    t.integer "household_id", null: false
    t.text "notes"
    t.integer "person_id", null: false
    t.integer "planned_meal_id"
    t.datetime "updated_at", null: false
    t.index ["household_id", "eaten_on"], name: "index_meals_on_household_id_and_eaten_on"
    t.index ["household_id"], name: "index_meals_on_household_id"
    t.index ["person_id", "eaten_on"], name: "index_meals_on_person_id_and_eaten_on"
    t.index ["person_id"], name: "index_meals_on_person_id"
    t.index ["planned_meal_id", "person_id"], name: "index_meals_on_planned_meal_and_person", unique: true, where: "planned_meal_id IS NOT NULL"
    t.index ["planned_meal_id"], name: "index_meals_on_planned_meal_id"
  end

  create_table "nutrients", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.integer "display_order", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "unit", null: false
    t.datetime "updated_at", null: false
    t.index ["display_order"], name: "index_nutrients_on_display_order", unique: true
    t.index ["key"], name: "index_nutrients_on_key", unique: true
    t.check_constraint "display_order > 0", name: "nutrients_positive_display_order"
  end

  create_table "pantry_items", force: :cascade do |t|
    t.string "confirmation_source", null: false
    t.datetime "confirmed_at", null: false
    t.integer "confirmed_by_id", null: false
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "ingredient_id", null: false
    t.integer "quantity_denominator"
    t.integer "quantity_numerator"
    t.string "state", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["confirmed_by_id"], name: "index_pantry_items_on_confirmed_by_id"
    t.index ["household_id", "ingredient_id"], name: "index_pantry_items_on_household_id_and_ingredient_id", unique: true
    t.index ["household_id"], name: "index_pantry_items_on_household_id"
    t.index ["ingredient_id"], name: "index_pantry_items_on_ingredient_id"
    t.check_constraint "(quantity_numerator IS NULL AND quantity_denominator IS NULL) OR (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)", name: "pantry_items_quantity_pair"
    t.check_constraint "quantity_denominator IS NULL OR quantity_denominator > 0", name: "pantry_items_positive_quantity_denominator"
    t.check_constraint "state <> 'confirmed' OR (quantity_numerator IS NOT NULL AND quantity_numerator > 0 AND unit IS NOT NULL)", name: "pantry_items_confirmed_amount"
    t.check_constraint "state = 'confirmed' OR (quantity_numerator IS NULL AND quantity_denominator IS NULL AND unit IS NULL)", name: "pantry_items_qualitative_amount"
    t.check_constraint "state IN ('confirmed', 'low', 'out', 'unknown')", name: "pantry_items_state"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "weekly_strength_sessions_target"
    t.integer "weekly_structured_minutes_target"
    t.integer "weekly_vigorous_minutes_target"
    t.integer "weekly_zone2_minutes_target"
    t.index ["household_id"], name: "index_people_on_household_id"
    t.check_constraint "weekly_strength_sessions_target IS NULL OR weekly_strength_sessions_target > 0", name: "people_positive_strength_sessions_target"
    t.check_constraint "weekly_structured_minutes_target IS NULL OR weekly_structured_minutes_target > 0", name: "people_positive_structured_minutes_target"
    t.check_constraint "weekly_vigorous_minutes_target IS NULL OR weekly_vigorous_minutes_target > 0", name: "people_positive_vigorous_minutes_target"
    t.check_constraint "weekly_zone2_minutes_target IS NULL OR weekly_zone2_minutes_target > 0", name: "people_positive_zone2_minutes_target"
  end

  create_table "person_habit_metrics", force: :cascade do |t|
    t.boolean "boolean_value"
    t.datetime "created_at", null: false
    t.integer "duration_value"
    t.integer "habit_metric_id", null: false
    t.decimal "number_value", precision: 12, scale: 3
    t.integer "person_habit_id", null: false
    t.time "time_of_day_value"
    t.datetime "updated_at", null: false
    t.index ["habit_metric_id"], name: "index_person_habit_metrics_on_habit_metric_id"
    t.index ["person_habit_id", "habit_metric_id"], name: "index_person_habit_metrics_on_configuration_and_metric", unique: true
    t.index ["person_habit_id"], name: "index_person_habit_metrics_on_person_habit_id"
    t.check_constraint "(CASE WHEN person_habit_metrics.number_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN person_habit_metrics.duration_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN person_habit_metrics.time_of_day_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN person_habit_metrics.boolean_value IS NULL THEN 0 ELSE 1 END) <= 1", name: "person_habit_metrics_one_typed_value"
    t.check_constraint "duration_value IS NULL OR duration_value >= 0", name: "person_habit_metrics_nonnegative_duration"
  end

  create_table "person_habits", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "friday", default: true, null: false
    t.integer "habit_id", null: false
    t.boolean "monday", default: true, null: false
    t.integer "person_id", null: false
    t.integer "position", null: false
    t.boolean "saturday", default: true, null: false
    t.boolean "sunday", default: true, null: false
    t.boolean "thursday", default: true, null: false
    t.boolean "tuesday", default: true, null: false
    t.datetime "updated_at", null: false
    t.boolean "wednesday", default: true, null: false
    t.index ["habit_id"], name: "index_person_habits_on_habit_id"
    t.index ["person_id", "habit_id"], name: "index_person_habits_on_person_id_and_habit_id", unique: true
    t.index ["person_id", "position"], name: "index_person_habits_on_person_id_and_position"
    t.index ["person_id"], name: "index_person_habits_on_person_id"
    t.check_constraint "position > 0", name: "person_habits_positive_position"
  end

  create_table "planned_meal_ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "decision", default: "unknown", null: false
    t.string "display_name", null: false
    t.text "display_quantity"
    t.integer "ingredient_id", null: false
    t.integer "planned_meal_id", null: false
    t.integer "position", null: false
    t.integer "quantity_denominator"
    t.integer "quantity_numerator"
    t.string "replacement_decision"
    t.string "replacement_display_name"
    t.text "replacement_display_quantity"
    t.integer "replacement_ingredient_id"
    t.integer "replacement_quantity_denominator"
    t.integer "replacement_quantity_numerator"
    t.string "replacement_unit"
    t.integer "source_recipe_id"
    t.integer "source_recipe_ingredient_id"
    t.datetime "superseded_at"
    t.string "superseded_reason"
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_planned_meal_ingredients_on_ingredient_id"
    t.index ["planned_meal_id", "position"], name: "index_planned_meal_ingredients_on_planned_meal_id_and_position"
    t.index ["planned_meal_id", "source_recipe_ingredient_id"], name: "index_planned_meal_ingredients_on_active_source", unique: true, where: "superseded_at IS NULL"
    t.index ["planned_meal_id"], name: "index_planned_meal_ingredients_on_planned_meal_id"
    t.index ["replacement_ingredient_id"], name: "index_planned_meal_ingredients_on_replacement_ingredient_id"
    t.index ["source_recipe_id"], name: "index_planned_meal_ingredients_on_source_recipe_id"
    t.index ["source_recipe_ingredient_id"], name: "index_planned_meal_ingredients_on_source_recipe_ingredient_id"
    t.check_constraint "(quantity_numerator IS NULL AND quantity_denominator IS NULL) OR (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)", name: "planned_meal_ingredients_quantity_pair"
    t.check_constraint "(replacement_quantity_numerator IS NULL AND replacement_quantity_denominator IS NULL) OR (replacement_quantity_numerator IS NOT NULL AND replacement_quantity_denominator IS NOT NULL)", name: "planned_meal_ingredients_replacement_quantity_pair"
    t.check_constraint "(superseded_at IS NULL AND superseded_reason IS NULL) OR (superseded_at IS NOT NULL AND superseded_reason IS NOT NULL)", name: "planned_meal_ingredients_supersession_pair"
    t.check_constraint "decision IN ('unknown', 'on_hand', 'missing', 'substituted', 'not_needed')", name: "planned_meal_ingredients_decision"
    t.check_constraint "position > 0", name: "planned_meal_ingredients_positive_position"
    t.check_constraint "quantity_denominator IS NULL OR quantity_denominator > 0", name: "planned_meal_ingredients_positive_quantity_denominator"
    t.check_constraint "replacement_decision IS NULL OR replacement_decision IN ('unknown', 'on_hand', 'missing')", name: "planned_meal_ingredients_replacement_decision"
    t.check_constraint "replacement_quantity_denominator IS NULL OR replacement_quantity_denominator > 0", name: "planned_meal_ingredients_positive_replacement_quantity_denominator"
    t.check_constraint "superseded_at IS NOT NULL OR (source_recipe_id IS NOT NULL AND source_recipe_ingredient_id IS NOT NULL)", name: "planned_meal_ingredients_active_source_present"
  end

  create_table "planned_meals", force: :cascade do |t|
    t.integer "allocation_priority"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "person_id"
    t.date "planned_on", null: false
    t.integer "recipe_id", null: false
    t.decimal "recipe_scale", precision: 10, scale: 3, default: "1.0", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "allocation_priority"], name: "index_planned_meals_on_household_id_and_allocation_priority"
    t.index ["household_id", "planned_on"], name: "index_planned_meals_on_household_id_and_planned_on"
    t.index ["household_id"], name: "index_planned_meals_on_household_id"
    t.index ["person_id", "planned_on"], name: "index_planned_meals_on_person_id_and_planned_on"
    t.index ["person_id"], name: "index_planned_meals_on_person_id"
    t.index ["recipe_id"], name: "index_planned_meals_on_recipe_id"
    t.check_constraint "allocation_priority IS NULL OR allocation_priority > 0", name: "planned_meals_positive_allocation_priority"
    t.check_constraint "recipe_scale > 0", name: "planned_meals_positive_recipe_scale"
  end

  create_table "planned_workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.date "scheduled_on", null: false
    t.string "skip_reason"
    t.datetime "skipped_at"
    t.integer "training_session_id"
    t.datetime "updated_at", null: false
    t.integer "workout_template_id", null: false
    t.index ["household_id", "scheduled_on"], name: "index_planned_workouts_on_household_id_and_scheduled_on"
    t.index ["household_id"], name: "index_planned_workouts_on_household_id"
    t.index ["person_id", "scheduled_on"], name: "index_planned_workouts_on_person_id_and_scheduled_on"
    t.index ["person_id"], name: "index_planned_workouts_on_person_id"
    t.index ["training_session_id"], name: "index_planned_workouts_on_training_session_id", unique: true
    t.index ["workout_template_id"], name: "index_planned_workouts_on_workout_template_id"
    t.check_constraint "skip_reason IS NULL OR skipped_at IS NOT NULL", name: "planned_workouts_reason_requires_skip"
    t.check_constraint "training_session_id IS NULL OR skipped_at IS NULL", name: "planned_workouts_session_or_skip"
  end

  create_table "recipe_feedbacks", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "meal_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["meal_item_id"], name: "index_recipe_feedbacks_on_meal_item_id", unique: true
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.text "display_quantity"
    t.decimal "gram_weight", precision: 10, scale: 3
    t.integer "ingredient_id", null: false
    t.text "notes"
    t.integer "position", null: false
    t.integer "quantity_denominator"
    t.integer "quantity_numerator"
    t.integer "recipe_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["id", "recipe_id"], name: "index_recipe_ingredients_on_id_and_recipe_id", unique: true
    t.index ["ingredient_id"], name: "index_recipe_ingredients_on_ingredient_id"
    t.index ["recipe_id", "position"], name: "index_recipe_ingredients_on_recipe_id_and_position", unique: true
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
    t.check_constraint "(quantity_numerator IS NULL AND quantity_denominator IS NULL) OR (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)", name: "recipe_ingredients_quantity_pair"
    t.check_constraint "gram_weight IS NULL OR gram_weight > 0", name: "recipe_ingredients_positive_gram_weight"
    t.check_constraint "position > 0", name: "recipe_ingredients_positive_position"
    t.check_constraint "quantity_denominator IS NULL OR quantity_denominator > 0", name: "recipe_ingredients_positive_quantity_denominator"
  end

  create_table "recipe_instruction_ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.integer "recipe_id", null: false
    t.integer "recipe_ingredient_id", null: false
    t.integer "recipe_instruction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id"], name: "index_recipe_instruction_ingredients_on_recipe_id"
    t.index ["recipe_ingredient_id"], name: "index_recipe_instruction_ingredients_on_recipe_ingredient_id"
    t.index ["recipe_instruction_id", "position"], name: "index_instruction_ingredients_on_instruction_and_position", unique: true
    t.index ["recipe_instruction_id", "recipe_ingredient_id"], name: "index_instruction_ingredients_on_instruction_and_ingredient", unique: true
    t.index ["recipe_instruction_id"], name: "index_recipe_instruction_ingredients_on_recipe_instruction_id"
    t.check_constraint "position > 0", name: "recipe_instruction_ingredients_positive_position"
  end

  create_table "recipe_instructions", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.decimal "duration_amount", precision: 10, scale: 2
    t.string "duration_unit"
    t.integer "position", null: false
    t.integer "recipe_id", null: false
    t.decimal "temperature_amount", precision: 10, scale: 2
    t.string "temperature_unit"
    t.datetime "updated_at", null: false
    t.index ["id", "recipe_id"], name: "index_recipe_instructions_on_id_and_recipe_id", unique: true
    t.index ["recipe_id", "position"], name: "index_recipe_instructions_on_recipe_id_and_position", unique: true
    t.index ["recipe_id"], name: "index_recipe_instructions_on_recipe_id"
    t.check_constraint "(duration_amount IS NULL AND duration_unit IS NULL) OR (duration_amount IS NOT NULL AND duration_unit IS NOT NULL)", name: "recipe_instructions_duration_pair"
    t.check_constraint "(temperature_amount IS NULL AND temperature_unit IS NULL) OR (temperature_amount IS NOT NULL AND temperature_unit IS NOT NULL)", name: "recipe_instructions_temperature_pair"
    t.check_constraint "duration_amount IS NULL OR duration_amount > 0", name: "recipe_instructions_positive_duration"
    t.check_constraint "duration_unit IS NULL OR duration_unit IN ('seconds', 'minutes', 'hours')", name: "recipe_instructions_duration_unit"
    t.check_constraint "position > 0", name: "recipe_instructions_positive_position"
    t.check_constraint "temperature_unit IS NULL OR temperature_unit IN ('F', 'C')", name: "recipe_instructions_temperature_unit"
  end

  create_table "recipe_nutrient_values", force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 6, null: false
    t.datetime "created_at", null: false
    t.integer "nutrient_id", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["nutrient_id"], name: "index_recipe_nutrient_values_on_nutrient_id"
    t.index ["recipe_id", "nutrient_id"], name: "index_recipe_nutrient_values_on_recipe_id_and_nutrient_id", unique: true
    t.index ["recipe_id"], name: "index_recipe_nutrient_values_on_recipe_id"
    t.check_constraint "amount >= 0", name: "recipe_nutrient_values_nonnegative_amount"
  end

  create_table "recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "import_key"
    t.string "provenance_status", null: false
    t.decimal "serving_count", precision: 10, scale: 3
    t.string "source_name"
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "yield"
    t.index ["household_id", "import_key"], name: "index_recipes_on_household_and_import_key", unique: true, where: "import_key IS NOT NULL"
    t.index ["household_id", "provenance_status"], name: "index_recipes_on_household_id_and_provenance_status"
    t.index ["household_id"], name: "index_recipes_on_household_id"
    t.check_constraint "provenance_status IN ('personal', 'verified', 'adapted', 'observed')", name: "recipes_provenance_status"
    t.check_constraint "serving_count IS NULL OR serving_count > 0", name: "recipes_positive_serving_count"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shopping_list_item_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "planned_meal_ingredient_id", null: false
    t.integer "shopping_list_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["planned_meal_ingredient_id"], name: "index_shopping_list_item_sources_on_planned_meal_ingredient_id", unique: true
    t.index ["shopping_list_item_id"], name: "index_shopping_list_item_sources_on_shopping_list_item_id"
  end

  create_table "shopping_list_items", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "generated_key"
    t.integer "ingredient_id"
    t.string "name", null: false
    t.text "notes"
    t.string "quantity"
    t.integer "shopping_list_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.datetime "user_managed_at"
    t.index ["ingredient_id"], name: "index_shopping_list_items_on_ingredient_id"
    t.index ["shopping_list_id", "generated_key"], name: "index_shopping_items_on_list_and_generated_key", unique: true, where: "generated_key IS NOT NULL"
    t.index ["shopping_list_id"], name: "index_shopping_list_items_on_shopping_list_id"
  end

  create_table "shopping_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.datetime "updated_at", null: false
    t.date "week_start", null: false
    t.index ["household_id", "week_start"], name: "index_shopping_lists_on_household_id_and_week_start", unique: true
    t.index ["household_id"], name: "index_shopping_lists_on_household_id"
  end

  create_table "training_session_blocks", force: :cascade do |t|
    t.integer "actual_duration_seconds"
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "position", null: false
    t.string "snapshot_block_kind", null: false
    t.string "snapshot_dose_class", default: "none", null: false
    t.integer "snapshot_planned_duration_minutes"
    t.string "snapshot_title", null: false
    t.integer "training_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["training_session_id", "position"], name: "idx_on_training_session_id_position_e41e181bae", unique: true
    t.index ["training_session_id"], name: "index_training_session_blocks_on_training_session_id"
    t.check_constraint "actual_duration_seconds IS NULL OR actual_duration_seconds > 0", name: "training_session_blocks_positive_actual_duration"
    t.check_constraint "position > 0", name: "training_session_blocks_positive_position"
  end

  create_table "training_session_exercises", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "difficulty"
    t.integer "exercise_id"
    t.text "next_time_adjustment"
    t.text "notes"
    t.integer "position", null: false
    t.string "snapshot_dose_class", default: "none", null: false
    t.text "snapshot_equipment"
    t.text "snapshot_guidance"
    t.text "snapshot_load_guidance"
    t.string "snapshot_modality", null: false
    t.string "snapshot_movement_pattern", null: false
    t.string "snapshot_name", null: false
    t.boolean "snapshot_per_side", default: false, null: false
    t.string "snapshot_performance_kind", default: "reps", null: false
    t.integer "snapshot_rep_max"
    t.integer "snapshot_rep_min"
    t.integer "snapshot_rest_seconds"
    t.integer "snapshot_sets_count"
    t.integer "snapshot_target_count"
    t.string "snapshot_target_count_unit"
    t.decimal "snapshot_target_distance_amount", precision: 10, scale: 2
    t.string "snapshot_target_distance_unit"
    t.integer "snapshot_target_heart_rate_max"
    t.integer "snapshot_target_heart_rate_min"
    t.string "snapshot_target_heart_rate_unit"
    t.decimal "snapshot_target_rir", precision: 3, scale: 1
    t.decimal "snapshot_target_rpe", precision: 3, scale: 1
    t.string "snapshot_tempo_cue"
    t.integer "snapshot_work_seconds"
    t.text "soreness_or_pain"
    t.text "substitution"
    t.integer "training_session_block_id", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id"], name: "index_training_session_exercises_on_exercise_id"
    t.index ["training_session_block_id", "position"], name: "index_session_exercises_on_block_and_position", unique: true
    t.index ["training_session_block_id"], name: "index_training_session_exercises_on_training_session_block_id"
    t.check_constraint "difficulty IS NULL OR difficulty IN ('too_easy', 'about_right', 'too_hard')", name: "training_session_exercises_difficulty"
    t.check_constraint "position > 0", name: "training_session_exercises_positive_position"
    t.check_constraint "snapshot_performance_kind IN ('reps', 'duration', 'distance', 'count', 'interval')", name: "training_session_exercises_performance_kind"
    t.check_constraint "snapshot_target_count_unit IS NULL OR snapshot_target_count_unit IN ('laps', 'flights', 'steps')", name: "training_session_exercises_target_count_unit"
    t.check_constraint "snapshot_target_distance_unit IS NULL OR snapshot_target_distance_unit IN ('m', 'km', 'mi', 'ft')", name: "training_session_exercises_target_distance_unit"
    t.check_constraint "snapshot_target_heart_rate_unit IS NULL OR snapshot_target_heart_rate_unit IN ('bpm', 'percent_max')", name: "training_session_exercises_target_heart_rate_unit"
  end

  create_table "training_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.text "notes"
    t.date "performed_on", null: false
    t.integer "person_id", null: false
    t.string "snapshot_provenance_status"
    t.string "snapshot_source_name"
    t.string "snapshot_source_url"
    t.string "snapshot_title", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workout_template_id"
    t.index ["household_id"], name: "index_training_sessions_on_household_id"
    t.index ["person_id", "performed_on"], name: "index_training_sessions_on_person_id_and_performed_on"
    t.index ["person_id"], name: "index_training_sessions_on_person_id"
    t.index ["workout_template_id"], name: "index_training_sessions_on_workout_template_id"
  end

  create_table "training_sets", force: :cascade do |t|
    t.integer "average_heart_rate_bpm"
    t.boolean "completed", default: false, null: false
    t.integer "count"
    t.string "count_unit"
    t.datetime "created_at", null: false
    t.decimal "distance_amount", precision: 10, scale: 2
    t.string "distance_unit"
    t.string "dose_class", default: "none", null: false
    t.integer "duration_seconds"
    t.decimal "load_amount", precision: 8, scale: 2
    t.string "load_unit"
    t.text "notes"
    t.integer "peak_heart_rate_bpm"
    t.integer "position", null: false
    t.integer "reps"
    t.integer "rest_seconds"
    t.decimal "rir", precision: 3, scale: 1
    t.decimal "rpe", precision: 3, scale: 1
    t.integer "training_session_exercise_id", null: false
    t.datetime "updated_at", null: false
    t.index ["training_session_exercise_id", "position"], name: "index_training_sets_on_exercise_and_position", unique: true
    t.index ["training_session_exercise_id"], name: "index_training_sets_on_training_session_exercise_id"
    t.check_constraint "count_unit IS NULL OR count_unit IN ('laps', 'flights', 'steps')", name: "training_sets_count_unit"
    t.check_constraint "distance_unit IS NULL OR distance_unit IN ('m', 'km', 'mi', 'ft')", name: "training_sets_distance_unit"
    t.check_constraint "dose_class IN ('none', 'strength', 'zone2', 'vigorous')", name: "training_sets_dose_class"
    t.check_constraint "load_unit IS NULL OR load_unit IN ('lb', 'kg')", name: "training_sets_load_unit"
    t.check_constraint "position > 0", name: "training_sets_positive_position"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["person_id"], name: "index_users_on_person_id", unique: true
  end

  create_table "workout_blocks", force: :cascade do |t|
    t.string "block_kind", null: false
    t.datetime "created_at", null: false
    t.string "dose_class", default: "none", null: false
    t.text "notes"
    t.integer "planned_duration_minutes"
    t.integer "position", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "workout_template_id", null: false
    t.index ["workout_template_id", "position"], name: "index_workout_blocks_on_workout_template_id_and_position", unique: true
    t.index ["workout_template_id"], name: "index_workout_blocks_on_workout_template_id"
    t.check_constraint "block_kind IN ('warm_up', 'strength', 'zone2', 'hiit_interval', 'mobility', 'cooldown_recovery', 'other')", name: "workout_blocks_block_kind"
    t.check_constraint "dose_class IN ('none', 'strength', 'zone2', 'vigorous')", name: "workout_blocks_dose_class"
    t.check_constraint "planned_duration_minutes IS NULL OR planned_duration_minutes > 0", name: "workout_blocks_positive_duration"
    t.check_constraint "position > 0", name: "workout_blocks_positive_position"
  end

  create_table "workout_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "provenance_status", null: false
    t.string "source_name"
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "provenance_status"], name: "index_workout_templates_on_household_id_and_provenance_status"
    t.index ["household_id"], name: "index_workout_templates_on_household_id"
    t.check_constraint "provenance_status IN ('verified', 'adapted', 'observed', 'personal')", name: "workout_templates_provenance_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_audit_events", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_audit_events", "agent_sessions"
  add_foreign_key "agent_audit_events", "households"
  add_foreign_key "agent_audit_events", "people"
  add_foreign_key "agent_audit_events", "users", column: "actor_id"
  add_foreign_key "agent_citations", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_citations", "agent_messages", column: "message_id"
  add_foreign_key "agent_citations", "agent_sessions"
  add_foreign_key "agent_citations", "households"
  add_foreign_key "agent_citations", "people"
  add_foreign_key "agent_conversations", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_conversations", "households"
  add_foreign_key "agent_conversations", "people"
  add_foreign_key "agent_grants", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_grants", "agent_sessions"
  add_foreign_key "agent_grants", "households"
  add_foreign_key "agent_grants", "people"
  add_foreign_key "agent_grants", "sessions", column: "browser_session_id", on_delete: :nullify
  add_foreign_key "agent_grants", "users", column: "issued_by_id"
  add_foreign_key "agent_installations", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_installations", "households"
  add_foreign_key "agent_knowledge_submissions", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_knowledge_submissions", "agent_grants"
  add_foreign_key "agent_knowledge_submissions", "agent_messages", column: "message_id"
  add_foreign_key "agent_knowledge_submissions", "agent_sessions"
  add_foreign_key "agent_knowledge_submissions", "households"
  add_foreign_key "agent_knowledge_submissions", "people"
  add_foreign_key "agent_messages", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_messages", "agent_sessions"
  add_foreign_key "agent_messages", "households"
  add_foreign_key "agent_messages", "people"
  add_foreign_key "agent_messages", "users", column: "redacted_by_id"
  add_foreign_key "agent_mutation_executions", "agent_mutation_proposals", column: "mutation_proposal_id"
  add_foreign_key "agent_mutation_executions", "users", column: "executed_by_id"
  add_foreign_key "agent_mutation_proposals", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_mutation_proposals", "agent_grants"
  add_foreign_key "agent_mutation_proposals", "agent_sessions"
  add_foreign_key "agent_mutation_proposals", "households"
  add_foreign_key "agent_mutation_proposals", "people"
  add_foreign_key "agent_mutation_proposals", "users", column: "approved_by_id"
  add_foreign_key "agent_mutation_proposals", "users", column: "executed_by_id"
  add_foreign_key "agent_mutation_proposals", "users", column: "requested_by_id"
  add_foreign_key "agent_operational_authorizations", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_operational_authorizations", "agent_sessions"
  add_foreign_key "agent_operational_authorizations", "households"
  add_foreign_key "agent_operational_authorizations", "people"
  add_foreign_key "agent_operational_authorizations", "sessions", column: "browser_session_id", on_delete: :nullify
  add_foreign_key "agent_operational_authorizations", "users", column: "authorized_by_id"
  add_foreign_key "agent_permission_decisions", "agent_permission_requests", column: "permission_request_id"
  add_foreign_key "agent_permission_decisions", "users", column: "decided_by_id"
  add_foreign_key "agent_permission_requests", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_permission_requests", "agent_sessions"
  add_foreign_key "agent_permission_requests", "households"
  add_foreign_key "agent_permission_requests", "people"
  add_foreign_key "agent_permission_requests", "users", column: "redacted_by_id"
  add_foreign_key "agent_plans", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_plans", "agent_sessions"
  add_foreign_key "agent_plans", "households"
  add_foreign_key "agent_plans", "people"
  add_foreign_key "agent_profiles", "households"
  add_foreign_key "agent_runtime_statuses", "households"
  add_foreign_key "agent_sessions", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_sessions", "agent_installations", column: "installation_id"
  add_foreign_key "agent_sessions", "households"
  add_foreign_key "agent_sessions", "people"
  add_foreign_key "agent_sessions", "sessions", column: "browser_session_id", on_delete: :nullify
  add_foreign_key "agent_setup_requests", "households"
  add_foreign_key "agent_setup_requests", "users", column: "requested_by_id"
  add_foreign_key "agent_tool_activities", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_tool_activities", "agent_sessions"
  add_foreign_key "agent_tool_activities", "households"
  add_foreign_key "agent_tool_activities", "people"
  add_foreign_key "agent_tool_activities", "users", column: "redacted_by_id"
  add_foreign_key "agent_turns", "agent_conversations", column: "conversation_id"
  add_foreign_key "agent_turns", "agent_messages", column: "user_message_id"
  add_foreign_key "agent_turns", "agent_sessions"
  add_foreign_key "agent_turns", "households"
  add_foreign_key "agent_turns", "people"
  add_foreign_key "agent_turns", "sessions", column: "browser_session_id", on_delete: :cascade
  add_foreign_key "exercise_prescriptions", "exercises", on_delete: :restrict
  add_foreign_key "exercise_prescriptions", "workout_blocks"
  add_foreign_key "exercises", "households"
  add_foreign_key "habit_check_in_measurements", "habit_check_ins"
  add_foreign_key "habit_check_in_measurements", "habit_metrics"
  add_foreign_key "habit_check_ins", "person_habits"
  add_foreign_key "habit_metrics", "habits"
  add_foreign_key "habits", "households"
  add_foreign_key "ingredient_nutrient_values", "ingredients"
  add_foreign_key "ingredient_nutrient_values", "nutrients"
  add_foreign_key "ingredients", "households"
  add_foreign_key "meal_item_nutrient_values", "meal_items"
  add_foreign_key "meal_item_nutrient_values", "nutrients", on_delete: :nullify
  add_foreign_key "meal_items", "ingredients"
  add_foreign_key "meal_items", "meals", on_delete: :cascade
  add_foreign_key "meal_items", "recipes"
  add_foreign_key "meals", "households"
  add_foreign_key "meals", "people"
  add_foreign_key "meals", "planned_meals"
  add_foreign_key "pantry_items", "households"
  add_foreign_key "pantry_items", "ingredients"
  add_foreign_key "pantry_items", "people", column: "confirmed_by_id"
  add_foreign_key "people", "households"
  add_foreign_key "person_habit_metrics", "habit_metrics"
  add_foreign_key "person_habit_metrics", "person_habits"
  add_foreign_key "person_habits", "habits"
  add_foreign_key "person_habits", "people"
  add_foreign_key "planned_meal_ingredients", "ingredients"
  add_foreign_key "planned_meal_ingredients", "ingredients", column: "replacement_ingredient_id"
  add_foreign_key "planned_meal_ingredients", "planned_meals", on_delete: :cascade
  add_foreign_key "planned_meal_ingredients", "recipe_ingredients", column: "source_recipe_ingredient_id", on_delete: :nullify
  add_foreign_key "planned_meal_ingredients", "recipes", column: "source_recipe_id", on_delete: :nullify
  add_foreign_key "planned_meals", "households"
  add_foreign_key "planned_meals", "people"
  add_foreign_key "planned_meals", "recipes"
  add_foreign_key "planned_workouts", "households"
  add_foreign_key "planned_workouts", "people"
  add_foreign_key "planned_workouts", "training_sessions", on_delete: :nullify
  add_foreign_key "planned_workouts", "workout_templates"
  add_foreign_key "recipe_feedbacks", "meal_items", on_delete: :cascade
  add_foreign_key "recipe_ingredients", "ingredients"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_instruction_ingredients", "recipe_ingredients"
  add_foreign_key "recipe_instruction_ingredients", "recipe_ingredients", column: ["recipe_ingredient_id", "recipe_id"], primary_key: ["id", "recipe_id"]
  add_foreign_key "recipe_instruction_ingredients", "recipe_instructions"
  add_foreign_key "recipe_instruction_ingredients", "recipe_instructions", column: ["recipe_instruction_id", "recipe_id"], primary_key: ["id", "recipe_id"]
  add_foreign_key "recipe_instruction_ingredients", "recipes"
  add_foreign_key "recipe_instructions", "recipes"
  add_foreign_key "recipe_nutrient_values", "nutrients"
  add_foreign_key "recipe_nutrient_values", "recipes"
  add_foreign_key "recipes", "households"
  add_foreign_key "sessions", "users"
  add_foreign_key "shopping_list_item_sources", "planned_meal_ingredients", on_delete: :cascade
  add_foreign_key "shopping_list_item_sources", "shopping_list_items", on_delete: :cascade
  add_foreign_key "shopping_list_items", "ingredients"
  add_foreign_key "shopping_list_items", "shopping_lists", on_delete: :cascade
  add_foreign_key "shopping_lists", "households", on_delete: :cascade
  add_foreign_key "training_session_blocks", "training_sessions"
  add_foreign_key "training_session_exercises", "exercises", on_delete: :nullify
  add_foreign_key "training_session_exercises", "training_session_blocks"
  add_foreign_key "training_sessions", "households"
  add_foreign_key "training_sessions", "people"
  add_foreign_key "training_sessions", "workout_templates", on_delete: :nullify
  add_foreign_key "training_sets", "training_session_exercises"
  add_foreign_key "users", "people"
  add_foreign_key "workout_blocks", "workout_templates"
  add_foreign_key "workout_templates", "households"
end
