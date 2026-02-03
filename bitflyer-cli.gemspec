# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bitflyer/cli/version'

Gem::Specification.new do |spec|
  spec.name                              = 'bitflyer-cli'
  spec.version                           = Bitflyer::Cli::VERSION
  spec.required_ruby_version             = '>= 3.1'
  spec.authors                           = ['Yuji Ueki']
  spec.email                             = ['unhappychoice@gmail.com']
  spec.summary                           = 'CLI tool for Bitflyer'
  spec.description                       = 'CLI tool for Bitflyer'
  spec.homepage                          = 'https://github.com/bitflyer-tools/bitflyer-cli'
  spec.license                           = 'MIT'
  spec.files                             = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir                            = 'exe'
  spec.executables                       = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths                     = ['lib']


  spec.add_dependency 'bitflyer', '>= 2.0'
  spec.add_dependency 'bigdecimal'
  spec.add_dependency 'colorize', '>= 0.8.1', '< 1.2.0'
  spec.add_dependency 'thor', '>= 0.20', '< 1.6'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
end
