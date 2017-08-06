# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = 'bitflyer-cli'
  spec.version       = '0.2.1'
  spec.authors       = ['Yuji Ueki']
  spec.email         = ['unhappychoice@gmail.com']

  spec.summary       = 'CLI tool for Bitflyer'
  spec.description   = 'CLI tool for Bitflyer'
  spec.homepage      = 'https://github.com/unhappychoice/bitflyer-cli'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'thor', '~> 0.19.4'
  spec.add_dependency 'bitflyer', '~> 0.1.0'
  spec.add_dependency 'colorize', '~> 0.8.1'

  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
