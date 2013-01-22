# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rack_session_redis_store/version'

Gem::Specification.new do |gem|
  gem.name          = "rack_session_redis_store"
  gem.version       = RackSessionRedisStore::VERSION
  gem.authors       = ["Spring_MT"]
  gem.email         = ["today.is.sky.blue.sky@gmail.com"]
  gem.summary       = %q{Rack session using redis. Corresponding to Rails :flash}
  gem.homepage      = "https://github.com/SpringMT/rack_session_redis_store"

  gem.rubyforge_project = 'rack_session_redis_store'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'rack', '>= 1'
  gem.add_dependency 'redis_json_serializer', '>= 0'

  gem.description = <<description
description

end
