# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bytepump/version'
# rubocop:disable LineLength
Gem::Specification.new do |spec|
  spec.name          = 'bytepump'
  spec.version       = Bytepump::VERSION
  spec.authors       = ['Wander Hillen']
  spec.email         = ['wjw.hillen@gmail.com']
  spec.summary       = 'A simple gem to splice data between file descriptors.'
  spec.description   = 'Uses the linux splice syscall to rapidly transport data between file descriptors in kernel memory.'
  spec.homepage      = 'https://github.com/WJWH/bytepump'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.platform      = "x86_64-linux"
  
  spec.add_runtime_dependency 'io_splice'
  spec.add_runtime_dependency 'retriable'
  
  spec.add_development_dependency 'bundler', '~> 1.11'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
end
# rubocop:enable LineLength
