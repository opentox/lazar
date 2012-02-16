require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'
#require "./validate-owl.rb"

TASK_SERVICE_URI = "http://ot-dev.in-silico.ch/task"

class TaskTest < Test::Unit::TestCase

  def setup
  end

  def teardown
  end

  def test_create_and_complete
    task = OpenTox::Task.create TASK_SERVICE_URI do
      sleep 1
      "http://test.org"
    end
    assert_equal "Running", task.hasStatus
    task.wait_for_completion
    assert_equal "Completed", task.hasStatus
    assert_equal "http://test.org", task.resultURI
  end


  def test_rdf
    task = OpenTox::Task.all(TASK_SERVICE_URI).last
    assert_equal OpenTox::Task, task.class
    #validate_owl(task.uri)
  end

end
