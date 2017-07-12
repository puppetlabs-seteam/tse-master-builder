require 'spec_helper_acceptance'

describe 'Validate RBAC is working' do

    context 'Create New Role' do
      createrole = <<-EOS
      /opt/puppetlabs/puppet/bin/curl -s -w "%{http_code}" -k -X POST -H 'Content-Type: application/json' \
              https://`facter fqdn`:4433/rbac-api/v1/roles \
              -d '{"description":"","user_ids":[],"group_ids":[], \
              "display_name":"TEST ROLE","permissions":[{"object_type":"nodes","action":"view_data","instance":"*"}]}' \
              --cert /`puppet config print ssldir`/certs/`facter fqdn`.pem \
              --key /`puppet config print ssldir`/private_keys/`facter fqdn`.pem \
              --cacert /`puppet config print ssldir`/certs/ca.pem -o /dev/null
      EOS

      it 'should add role' do
        role_result = shell(createrole)
        expect(role_result.exit_code).to eq 0
        expect(role_result.stdout).to match(/303/)
      end
    end

    context 'Create New User in Role' do
      createuser = <<-EOS
        /opt/puppetlabs/puppet/bin/curl -s -w "%{http_code}" -k -X POST -H 'Content-Type: application/json' \
          https://`facter fqdn`:4433/rbac-api/v1/users \
          -d '{"login": "deploy_test", "password": "puppetlabs", "email": "", "display_name": "", "role_ids": [2,5]}' \
          --cert /`puppet config print ssldir`/certs/`facter fqdn`.pem \
          --key /`puppet config print ssldir`/private_keys/`facter fqdn`.pem \
          --cacert /`puppet config print ssldir`/certs/ca.pem -o /dev/null
      EOS

      it 'should add user' do
        user_result = shell(createuser)
        expect(user_result.exit_code).to eq 0
        expect(user_result.stdout).to match(/303/)
      end
    end

end
