# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "opentox-client"
  s.version     = File.read("./VERSION").strip
  s.authors     = ["Christoph Helma, Martin Guetlein, Andreas Maunz, Micha Rautenberg, David Vorgrimmler, Denis Gebele"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/lazar"
  s.summary     = %q{Ruby wrapper for the OpenTox REST API}
  s.description = %q{Ruby wrapper for the OpenTox REST API (http://www.opentox.org)}
  s.license     = 'GPL-3'

  s.rubyforge_project = "lazar"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_runtime_dependency "bundler"
  s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency 'nokogiri'
  s.add_runtime_dependency "openbabel"
  s.add_runtime_dependency 'rserve-client'
  s.add_runtime_dependency "mongoid", '~> 5.0beta'  

end
