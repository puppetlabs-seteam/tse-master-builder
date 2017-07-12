require 'spec_helper_acceptance'

describe 'Validate Services' do
  context 'Verify enabled/running' do
    [
      'puppet',
      'pe-puppetserver',
      'pe-activemq',
      'mcollective',
      'pe-puppetdb',
      'pe-postgresql',
      'pe-console-services',
      'pe-nginx',
      'pe-orchestration-services',
      'pxp-agent'
    ].each do |s|
      describe service(s) do
        it { is_expected.to be_enabled }
        it { is_expected.to be_running }
      end
    end
  end
end
