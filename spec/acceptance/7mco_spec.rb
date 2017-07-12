require 'spec_helper_acceptance'

describe 'Validate MCO is working' do

    context 'Execute MCO Ping' do

      run_job = <<-EOS
      sudo -u peadmin -i mco ping
      EOS

      it 'should execute successfully' do
        job_result = shell(run_job)
        expect(job_result.exit_code).to eq 0
      end

    end
end
