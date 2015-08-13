exclude = ["./setup.rb","./all.rb"]
(Dir[File.join(File.dirname(__FILE__),"*.rb")]-exclude).each do |test|
  p test 
  require_relative test
end
