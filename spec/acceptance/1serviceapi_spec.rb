require 'spec_helper_acceptance'

describe 'Validate General Service Status' do
  context 'Check Service Status API' do

    it  'all services should be in running state' do
      run_job = <<-EOS
      curl https://$(hostname -f):4433/status/v1/services \
        --cert /etc/puppetlabs/puppet/ssl/certs/$(hostname -f) \
        --key /etc/puppetlabs/puppet/ssl/private_keys/$(hostname -f) \
        --cacert /etc/puppetlabs/puppet/ssl/certs/ca.pem
      EOS

      job_result = shell(run_job)
      expect(job_result.exit_code).to eq 0

      status = JSON.parse(job_result.stdout)
      status.keys.each do |s|
        expect(status[s]['state']).to match(/running/)
      end

    end
  end
end
