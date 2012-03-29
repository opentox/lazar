require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.expand_path(File.join(File.dirname(__FILE__),'..','lib','opentox-client.rb'))
TEST_URI  = "http://only_a_test/test/" + rand(1000000).to_s
AA ||= "https://opensso.in-silico.ch"
AA_USER = "guest"
AA_PASS = "guest"
@@subjectid = OpenTox::Authorization.authenticate(AA_USER,AA_PASS)

class TestOpenToxAuthorizationBasic < Test::Unit::TestCase
 
  def test_01_server
    assert_equal(AA, OpenTox::Authorization.server)
  end
 
  def test_02_get_token
    assert_not_nil @@subjectid
  end
  
  def test_03_is_valid_token
    tok = login
    assert_not_nil tok
    assert OpenTox::Authorization.is_token_valid(tok)
    logout(tok)
  end
  
  def test_04_logout
    tok = login
    assert logout(tok)
    assert_equal false, OpenTox::Authorization.is_token_valid(tok)
  end
  
  def test_05_list_policies
    assert_kind_of Array, OpenTox::Authorization.list_policies(@@subjectid)
  end
  
end

class TestOpenToxAuthorizationLDAP < Test::Unit::TestCase

  def test_01_list_user_groups
    assert_kind_of Array, OpenTox::Authorization.list_user_groups(AA_USER, @@subjectid)
  end
  
  def test_02_get_user
    assert_equal AA_USER, OpenTox::Authorization.get_user(@@subjectid)
  end

end

class TestOpenToxAuthorizationLDAP < Test::Unit::TestCase

  def test_01_create_check_delete_default_policies
    res = OpenTox::Authorization.send_policy(TEST_URI, @@subjectid)
    assert res
    assert OpenTox::Authorization.uri_has_policy(TEST_URI, @@subjectid)
    policies = OpenTox::Authorization.list_uri_policies(TEST_URI, @@subjectid)
    assert_kind_of Array, policies
    policies.each do |policy|
      assert OpenTox::Authorization.delete_policy(policy, @@subjectid)
    end
    assert_equal false, OpenTox::Authorization.uri_has_policy(TEST_URI, @@subjectid)
  end

  def test_02_check_policy_rules
    tok_anonymous = OpenTox::Authorization.authenticate("anonymous","anonymous")
    assert_not_nil tok_anonymous
    res = OpenTox::Authorization.send_policy(TEST_URI, @@subjectid)
    assert res
    assert OpenTox::Authorization.uri_has_policy(TEST_URI, @@subjectid)
    owner_rights = {"GET" => true, "POST" => true, "PUT" => true, "DELETE" => true}
    groupmember_rights = {"GET" => true, "POST" => nil, "PUT" => nil, "DELETE" => nil}
    owner_rights.each do |request, right|
      assert_equal right, OpenTox::Authorization.authorize(TEST_URI, request, @@subjectid), "#{AA_USER} requests #{request} to #{TEST_URI}"
    end
    groupmember_rights.each do |request, r|
      assert_equal r, OpenTox::Authorization.authorize(TEST_URI, request, tok_anonymous), "anonymous requests #{request} to #{TEST_URI}"
    end
    
    policies = OpenTox::Authorization.list_uri_policies(TEST_URI, @@subjectid)
    assert_kind_of Array, policies
    policies.each do |policy|
      assert OpenTox::Authorization.delete_policy(policy, @@subjectid)
    end
    logout(tok_anonymous)
  end

  def test_03_check_different_uris
    res = OpenTox::Authorization.send_policy(TEST_URI, @@subjectid)
    assert OpenTox::Authorization.uri_has_policy(TEST_URI, @@subjectid)
    assert OpenTox::Authorization.authorize(TEST_URI, "GET", @@subjectid), "GET request"
    policies = OpenTox::Authorization.list_uri_policies(TEST_URI, @@subjectid)
    policies.each do |policy|
      assert OpenTox::Authorization.delete_policy(policy, @@subjectid)
    end
 
  end  
end


def logout (token)
   OpenTox::Authorization.logout(token)
end

def login
  OpenTox::Authorization.authenticate(AA_USER,AA_PASS)
end 