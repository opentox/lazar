# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "lazar"
  s.version     = File.read("./VERSION").strip
  s.authors     = ["Christoph Helma, Martin Guetlein, Andreas Maunz, Micha Rautenberg, David Vorgrimmler, Denis Gebele"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/lazar"
  s.summary     = %q{Lazar framework}
  s.description = %q{Libraries for lazy structure-activity relationships and read-across.}
  s.license     = 'GPL-3'

  s.rubyforge_project = "lazar"

  s.files         = Dir["lib/*rb"]
  s.test_files    = Dir["test/*rb"]
  s.extensions    = %w[ext/lazar/extconf.rb]
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_runtime_dependency "bundler"
  s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency 'nokogiri'
  s.add_runtime_dependency 'rserve-client'
  s.add_runtime_dependency "mongoid", '~> 5.0beta'  

end
