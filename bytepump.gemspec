# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bytepump/version'

Gem::Specification.new do |spec|
  spec.name          = "bytepump"
  spec.version       = Bytepump::VERSION
  spec.authors       = ["Wander Hillen"]
  spec.email         = ["wjw.hillen@gmail.com"]
  spec.summary       = %q{A simple gem to splice data between file descriptors.}
  spec.description   = %q{Uses the linux splice syscall to rapidly transport data between file descriptors in kernel memory.}
  spec.homepage      = "https://github.com/WJWH/bytepump"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/extconf.rb"] #include the C files

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
