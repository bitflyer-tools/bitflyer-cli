# frozen_string_literal: true

require 'yaml'

RSpec.describe 'Test workflow' do
  it 'runs RSpec without a Codecov token' do
    workflow = YAML.safe_load_file(File.expand_path('../.github/workflows/test.yml', __dir__))
    job = workflow.fetch('jobs').fetch('test')
    rspec_step = job.fetch('steps').find { |step| step['run'] == 'bundle exec rspec' }

    expect(rspec_step).to be_a(Hash)
    [workflow, job, rspec_step].each do |scope|
      expect(scope.fetch('env', {})).not_to have_key('CODECOV_TOKEN')
    end
  end
end
