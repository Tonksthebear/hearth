require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "fixtures represent two people in one household" do
    assert_equal 2, User.count
    assert_not_equal users(:one).person, users(:two).person
    assert_equal users(:one).person.household, users(:two).person.household
  end

  test "authenticates with a secure password" do
    assert_equal users(:one), User.authenticate_by(email_address: "ONE@EXAMPLE.COM", password: "password")
    assert_nil User.authenticate_by(email_address: "one@example.com", password: "wrong")
  end

  test "destroys persisted sessions with the user" do
    user = users(:one)
    session = user.sessions.create!

    assert_difference "Session.count", -1 do
      user.destroy!
    end

    assert_not Session.exists?(session.id)
  end

  test "database requires one distinct person per user" do
    attributes = {
      email_address: "another@example.com",
      password_digest: users(:one).password_digest,
      created_at: Time.current,
      updated_at: Time.current
    }

    assert_raises ActiveRecord::RecordNotUnique do
      User.insert_all!([ attributes.merge(person_id: people(:one).id) ])
    end

    assert_raises ActiveRecord::NotNullViolation do
      User.insert_all!([ attributes.merge(email_address: "missing-person@example.com", person_id: nil) ])
    end
  end
end
