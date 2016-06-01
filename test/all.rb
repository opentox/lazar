# "./default_environment.rb" has to be executed separately
exclude = ["./setup.rb","./all.rb", "./default_environment.rb",]
(Dir[File.join(File.dirname(__FILE__),"*.rb")]-exclude).each do |test|
  require_relative test
end
