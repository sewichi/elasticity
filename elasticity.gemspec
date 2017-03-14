# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib', __FILE__)
require 'elasticity/version'

Gem::Specification.new do |s|
  s.name        = 'placed-elasticity'
  s.version     = Elasticity::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Robert Slifka']
  s.homepage    = 'http://www.github.com/rslifka/elasticity'
  s.summary     = %q{Streamlined, programmatic access to Amazon's Elastic Map Reduce service.}
  s.description = %q{Streamlined, programmatic access to Amazon's Elastic Map Reduce service, driven by the Sharethrough team's requirements for belting out EMR jobs.}

  s.add_dependency('rest-client', '~> 1.8.0')
  s.add_dependency('nokogiri', '~> 1.6.0')
  s.add_dependency('fog', '~> 1.25.0')
  s.add_dependency('fog-core', '~> 1.25.0')

  s.add_development_dependency('rake', '~> 10.1.0')
  s.add_development_dependency('rspec', '~> 2.12.0')
  s.add_development_dependency('timecop', '~> 0.5')
  s.add_development_dependency('fakefs', '~> 0.4')

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = %w(lib)
end
