require 'spec_helper_acceptance'

describe 'Validate PuppetDB is working' do

    context 'Execute PuppetDB Query' do

      run_job = <<-EOS
      puppet-query 'facts[]{}'|wc -l
      EOS

      it 'should execute successfully' do
        job_result = shell(run_job)
        expect(job_result.exit_code).to eq 0
        expect(job_result.stdout.to_i).not_to eq 0
      end

    end
end
