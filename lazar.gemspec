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
  s.license     = 'GPL-3.0'

  s.rubyforge_project = "lazar"
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.extensions    = %w[ext/lazar/extconf.rb]
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_runtime_dependency 'bundler', '~> 1.11'
  s.add_runtime_dependency 'rest-client', '~> 1.8'
  s.add_runtime_dependency 'nokogiri', '~> 1.6'
  s.add_runtime_dependency 'rserve-client', '~> 0.3'
  s.add_runtime_dependency 'mongoid', '~> 5.0'
  s.add_runtime_dependency 'openbabel', '~> 2.3', '>= 2.3.2.2'

end
