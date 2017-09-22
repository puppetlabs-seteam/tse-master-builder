require 'spec_helper_acceptance'

describe 'Validate Ports' do
  context 'Verify Listening ' do
    [
      81,
      8140,
      8142,
      8143,
      61613,
      4433,
      443,
    ].each do |p|
      describe port(p) do
        it { should be_listening }
      end
    end
  end
end
