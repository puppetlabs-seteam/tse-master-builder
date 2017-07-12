require 'spec_helper_acceptance'

describe 'Validate Orchestration is working' do

    context 'Execute Puppet Job Run ' do

      run_job = <<-EOS
      /opt/puppetlabs/bin/puppet-job run --nodes `hostname -f`
      EOS

      it 'should run successfully' do
        job_result = shell(run_job)
        expect(job_result.exit_code).to eq 0
      end

    end
end
