# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rm-extensions-firebase/version'

Gem::Specification.new do |gem|
  gem.name          = "rm-extensions-firebase"
  gem.version       = RMExtensions::Firebase::VERSION
  gem.authors       = ["Joe Noon"]
  gem.email         = ["joenoon@gmail.com"]
  gem.description   = %q{Experimental rubymotion wrapper for firebase}
  gem.summary       = %q{Experimental rubymotion wrapper for firebase}
  gem.homepage      = "https://github.com/joenoon/rm-extensions-firebase"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_dependency "rm-extensions", "~> 0.5.2"
end
