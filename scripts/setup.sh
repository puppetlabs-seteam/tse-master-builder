#!/bin/bash
set -x
export PATH=$PATH:/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin

#Setup Prereqs
function setup_prereqs {
  yum -y install wget
  mkdir -p /etc/puppetlabs/puppetserver/ssh/
  mkdir -p /etc/puppetlabs/puppet
  yum -y install open-vm-tools

  hostnamectl set-hostname master.inf.puppet.vm
  echo '127.0.0.1  master.inf.puppet.vm master' > /etc/hosts
  cat /etc/hosts
  echo 'nameserver 8.8.8.8' > /etc/resolv.conf
  yum clean all
}

function setup_users {
  usermod --password '$6$oDTfITCj$/RDXWiYpkTSUcJjfMfEdPsncaHWGW2FC8PoW39MgELECnwhcBmtxx00E4EnTwkhr1s4eaWz6aANuhE3w4cjE81' root
}

#Generate SSH Keys
function generate_keys {
  ssh-keygen -t rsa -b 4096 -N "" -f /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa
}

#Download PE
function download_pe {
  #https://github.com/glarizza/pe_curl_requests/blob/master/installer/download_pe_tarball.sh
  DOWNLOAD_MVER=$(echo $DOWNLOAD_VERSION|awk -F '.' '{print $1"."$2}')

  if [ $DOWNLOAD_RC -eq 0 ]; then
    DOWNLOAD_URL="http://enterprise.delivery.puppetlabs.net/${DOWNLOAD_MVER}/ci-ready/puppet-enterprise-${DOWNLOAD_VERSION}-${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}-${DOWNLOAD_ARCH}.tar"
    TAR_OPTS="-xf"
    TAR_NAME="puppet-enterprise-${DOWNLOAD_VERSION}-${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}-${DOWNLOAD_ARCH}.tar"
  else
    DOWNLOAD_URL="https://pm.puppetlabs.com/cgi-bin/download.cgi?dist=${DOWNLOAD_DIST}&rel=${DOWNLOAD_RELEASE}&arch=${DOWNLOAD_ARCH}&ver=${DOWNLOAD_VERSION}"
    TAR_OPTS="-xzf"
    TAR_NAME="puppet-enterprise-${DOWNLOAD_VERSION}-${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}-${DOWNLOAD_ARCH}.tar.gz"
  fi

  echo "Downloading PE $DOWNLOAD_VERSION for ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}-${DOWNLOAD_ARCH} to: ${TAR_NAME}"
  echo
  curl --progress-bar \
    -L \
    -o "./${TAR_NAME}" \
    -C - \
    $DOWNLOAD_URL

  tar $TAR_OPTS $TAR_NAME -C /tmp/
}

# Install Agent
function install_agent {
  rpm -Uhv /tmp/puppet-enterprise-$DOWNLOAD_VERSION-$DOWNLOAD_DIST-$DOWNLOAD_RELEASE-$DOWNLOAD_ARCH/packages/el-7-x86_64/puppet-agent-*.rpm
}

#Setup PE
function install_pe {
  echo "${LIC_KEY}" > /etc/puppetlabs/license.key
  cat > /etc/puppetlabs/puppet/csr_attributes.yaml << YAML
  extension_requests:
      pp_role:  master_server
YAML
  cat > /tmp/pe.conf << FILE
"console_admin_password": "puppetlabs"
"puppet_enterprise::puppet_master_host": "%{::trusted.certname}"
"puppet_enterprise::profile::master::code_manager_auto_configure": true
"puppet_enterprise::profile::master::r10k_remote": "git@localhost:puppet/control-repo.git"
"puppet_enterprise::profile::master::r10k_private_key": "/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa"
FILE
  /tmp/puppet-enterprise-$DOWNLOAD_VERSION-$DOWNLOAD_DIST-$DOWNLOAD_RELEASE-$DOWNLOAD_ARCH/puppet-enterprise-installer -c /tmp/pe.conf
  chown -R pe-puppet:pe-puppet /etc/puppetlabs/puppetserver/ssh
}

#Setup Code Manager

function add_pe_users {
/opt/puppetlabs/puppet/bin/curl -k -X POST -H 'Content-Type: application/json' \
        https://`facter fqdn`:4433/rbac-api/v1/roles \
        https://`facter fqdn`:4433/rbac-api/v1/roles \
        -d '{"description":"","user_ids":[],"group_ids":[],"display_name":"Node Data Viewer","permissions":[{"object_type":"nodes","action":"view_data","instance":"*"}]}' \
        --cert /`puppet config print ssldir`/certs/`facter fqdn`.pem \
        --key /`puppet config print ssldir`/private_keys/`facter fqdn`.pem \
        --cacert /`puppet config print ssldir`/certs/ca.pem

  /opt/puppetlabs/puppet/bin/curl -k -X POST -H 'Content-Type: application/json' \
          https://`facter fqdn`:4433/rbac-api/v1/users \
          -d '{"login": "deploy", "password": "puppetlabs", "email": "", "display_name": "", "role_ids": [2,5]}' \
          --cert /`puppet config print ssldir`/certs/`facter fqdn`.pem \
          --key /`puppet config print ssldir`/private_keys/`facter fqdn`.pem \
          --cacert /`puppet config print ssldir`/certs/ca.pem

  /opt/puppetlabs/bin/puppet-access login deploy --lifetime=1y << TEXT
puppetlabs
TEXT
}

function setup_git {
  # set up gitea
  /opt/puppetlabs/bin/puppet module install kogitoapp-gitea --version 1.0.4
  cat > /tmp/git.pp << 'FILE'
  class { 'gitea':
      package_ensure         => 'present',
      dependencies_ensure    => 'present',
      dependencies           => ['curl', 'git', 'tar'],
      manage_user            => true,
      manage_group           => true,
      manage_home            => true,
      owner                  => 'git',
      group                  => 'git',
      home                   => '/home/git',
      version                => '1.4.2',
      checksum               => 'c843d462b5edb0d64572b148a0e814e41d069d196c3b3ee491449225e1c39d7d',
      checksum_type          => 'sha256',
      installation_directory => '/opt/gitea',
      repository_root        => '/var/git',
      log_directory          => '/var/log/gitea',
      attachment_directory   => '/opt/gitea/data/attachments',
      manage_service         => true,
      service_template       => 'gitea/systemd.erb',
      service_path           => '/lib/systemd/system/gitea.service',
      service_provider       => 'systemd',
      service_mode           => '0644',
      configuration_sections => {
        'server'     => {
          'DOMAIN'           => $::fqdn,
          'HTTP_PORT'        => 3000,
          'ROOT_URL'         => "https://${::fqdn}/",
          'HTTP_ADDR'        => '0.0.0.0',
          'DISABLE_SSH'      => false,
          'SSH_PORT'         => '22',
          'START_SSH_SERVER' => false,
          'OFFLINE_MODE'     => false,
        },
        'database'   => {
          'DB_TYPE'  => 'sqlite3',
          'HOST'     => '127.0.0.1:3306',
          'NAME'     => 'gitea',
          'USER'     => 'root',
          'PASSWD'   => '',
          'SSL_MODE' => 'disable',
          'PATH'     => '/opt/gitea/data/gitea.db',
        },
        'security'   => {
          'SECRET_KEY'   => 'thesecretkey',
          'INSTALL_LOCK' => true,
        },
        'service'    => {
          'REGISTER_EMAIL_CONFIRM' => false,
          'ENABLE_NOTIFY_MAIL'     => false,
          'DISABLE_REGISTRATION'   => false,
          'ENABLE_CAPTCHA'         => true,
          'REQUIRE_SIGNIN_VIEW'    => false,
        },
        'repository' => {
          'ROOT'     => '/var/git',
        },
        'mailer'     => {
          'ENABLED' => false,
        },
        'picture'    => {
          'DISABLE_GRAVATAR'        => false,
          'ENABLE_FEDERATED_AVATAR' => true,
        },
        'session'    => {
          'PROVIDER' => 'file',
        },
        'indexer'    => {
          'REPO_INDEXER_ENABLED' => true,
        },        
        'log'        => {
          'MODE'      => 'file',
          'LEVEL'     => 'info',
          'ROOT_PATH' => '/opt/gitea/log',
        },
        'webhook'    => {
          'SKIP_TLS_VERIFY' => true,
        },
      }
  }

FILE

  /opt/puppetlabs/bin/puppet apply /tmp/git.pp

  cd /tmp
  sleep 5
  sudo -u git /opt/gitea/gitea admin create-user --name=puppet --password=puppetlabs --email='puppet@localhost.local' --admin=true
  for i in 1 2 3 4 5
  do
    if [ $? -ne 0 ]; then
      echo "Attempting to create user again $i"
      sudo -u git /opt/gitea/gitea admin create-user --name=puppet --password=puppetlabs --email='puppet@localhost.local' --admin=true
    fi  
  done

  if [ $? -ne 0 ]; then
    echo "gitea: Puppet user wasnt created."
    exit 7
  fi  

  echo "{\"clone_addr\": \"${GIT_REMOTE}\", \"uid\": 1, \"repo_name\": \"control-repo\"}" > repo.data
  curl -H 'Content-Type: application/json' -X POST -d @repo.data http://puppet:puppetlabs@localhost:3000/api/v1/repos/migrate

  for j in 1 2 3 4 5
  do
    if [ $? -ne 0 ]; then
      echo "Attempting to migrate repos again $j"
      curl -H 'Content-Type: application/json' -X POST -d @repo.data http://puppet:puppetlabs@localhost:3000/api/v1/repos/migrate
    fi  
  done

  if [ $? -ne 0 ]; then
    echo "gitea: Failed to create control-repo"
    exit 5
  fi

  PUB_KEY=$(cat /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa.pub)
  echo "{\"title\":\"puppet master key\",\"key\":\""${PUB_KEY}"\"}" > input.data
  curl -H 'Content-Type: application/json' -X POST -d @input.data http://puppet:puppetlabs@localhost:3000/api/v1/admin/users/puppet/keys
  if [ $? -ne 0 ]; then
    echo "gitea: Failed to create public key"
    exit 6
  fi

  # Reset hard back to our build version
  echo "Resetting to build version..."
  mkdir ~/.ssh
  chmod 700 ~/.ssh
  ssh-keyscan localhost > ~/.ssh/known_hosts
  echo -e "Host localhost\n\tIdentityFile /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa" > ~/.ssh/config
  git clone git@localhost:puppet/control-repo.git control-repo
  cd control-repo
  git reset --hard $BUILD_VER
  git push origin production -f

  # Prune non-production branches
  echo "Pruning branches...."

  for i in $(git branch -a|grep -v production|awk -F '/' '{print $3}')
  do
    git push origin :${i}
  done
  cd ../

  rm -rf /tmp/control-repo
  rm /tmp/git.pp
  rm /tmp/repo.data
  rm /tmp/input.data

}

#Deploy Code
function deploy_code_pe {
  /opt/puppetlabs/bin/puppet-code deploy production -w
}

function setup_hiera_pe {
  /opt/puppetlabs/bin/puppetserver gem install hiera-eyaml
  /opt/puppetlabs/puppet/bin/gem install hiera-eyaml
  if [ -f /vagrant/keys/private_key.pkcs7.pem ]
    then
      rm /etc/puppetlabs/puppet/keys/*
      cp /vagrant/keys/private_key.pkcs7.pem /etc/puppetlabs/puppet/keys/.
      cp /vagrant/keys/public_key.pkcs7.pem /etc/puppetlabs/puppet/keys/.
  fi
}

#Kick Off First Puppet Run
function run_puppet {
  cd /
  /opt/puppetlabs/bin/puppet agent -t
}

# Generate Offline Control Repo
function offline_control_repo {
  /opt/puppetlabs/puppet/bin/ruby /etc/puppetlabs/code/environments/production/scripts/local_control_repo.rb \
    -c /home/git/puppetpov/control-repo.git \
    -o /home/git/puppetpov/offline-control-repo.git
  chown -R git:git /home/git/puppetpov/offline-control-repo.git
}

#Remove Certs and Sanitize Hostname in puppet.conf
function clean_certs {
  /opt/puppetlabs/bin/puppet apply -e "include profile::puppet::clean_certs"
}

function vagrant_setup {
  id vagrant &>/dev/null || useradd -m vagrant
  mkdir /home/vagrant/.ssh
  wget --no-check-certificate https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub -O /home/vagrant/.ssh/authorized_keys
  wget --no-check-certificate https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant -O /home/vagrant/.ssh/id_rsa
  chmod 700 /home/vagrant/.ssh
  chmod 600 /home/vagrant/.ssh/authorized_keys
  chown -R vagrant:vagrant /home/vagrant/.ssh
  echo "vagrant" | passwd --stdin vagrant
  cat > /etc/sudoers.d/10_sudovagrant << SUDOVAGRANT
vagrant ALL=(ALL) NOPASSWD: ALL
SUDOVAGRANT
}

function guest_additions {
  yum groupinstall "Development Tools"
  yum install -y gcc kernel-devel kernel-headers dkms make bzip2 perl
  mkdir /tmp/vboxguest
  wget http://download.virtualbox.org/virtualbox/5.1.14/VBoxGuestAdditions_5.1.14.iso
  KERN_DIR=/usr/src/kernels/`uname -r`
  export KERN_DIR
  mkdir /media/VBoxGuestAdditions
  mount -o loop,ro VBoxGuestAdditions_5.1.14.iso /media/VBoxGuestAdditions
  sh /media/VBoxGuestAdditions/VBoxLinuxAdditions.run
  rm VBoxGuestAdditions_5.1.14.iso
  umount /media/VBoxGuestAdditions
  rmdir /media/VBoxGuestAdditions
}

function add_gitea_webhook {
  echo "{\"type\":\"gitea\",\"config\":\
    {\"url\":\"https://localhost:8170/code-manager/v1/webhook?type=github&token=$(cat /root/.puppetlabs/token)\",\"content_type\":\"json\"},\
    \"events\":[\"push\"],\"active\":true}" > hook.data
  curl -H 'Content-Type: application/json' -X POST -d @hook.data http://puppet:puppetlabs@localhost:3000/api/v1/repos/puppet/control-repo/hooks
  rm -f hook.data
}

function cleanup {
  rm -rf /tmp/puppet-enterprise*
  rm -f  /root/puppet-enterprise-*.tar.gz
  rm -f /etc/puppetlabs/license.key

  if [ "$PACKER_BUILDER_TYPE" != "virtualbox-ovf" ]; then
    rm -f /etc/sudoers.d/10_vagrant
  fi
}

function free_disk_space {
  # Adopting from https://github.com/boxcutter/centos/blob/master/script/cleanup.sh
  DISK_USAGE_BEFORE_CLEANUP=$(df -h)

  echo "==> Clean up yum cache of metadata and packages to save space"
  yum -y --enablerepo='*' clean all

  echo "==> Removing temporary files used to build box"
  rm -rf /tmp/*

  echo "==> Rebuild RPM DB"
  rpmdb --rebuilddb
  rm -f /var/lib/rpm/__db*

  # delete any logs that have built up during the install
  find /var/log/ -name *.log -exec rm -f {} \;

  echo '==> Clear out swap and disable until reboot'
  set +e
  swapuuid=$(/sbin/blkid -o value -l -s UUID -t TYPE=swap)
  case "$?" in
    2|0) ;;
    *) exit 1 ;;
  esac
  set -e
  if [ "x${swapuuid}" != "x" ]; then
      # Whiteout the swap partition to reduce box size
      # Swap is disabled till reboot
      swappart=$(readlink -f /dev/disk/by-uuid/$swapuuid)
      /sbin/swapoff "${swappart}"
      dd if=/dev/zero of="${swappart}" bs=1M || echo "dd exit code $? is suppressed"
      /sbin/mkswap -U "${swapuuid}" "${swappart}"
  fi

  echo '==> Zeroing out empty area to save space in the final image'
  # Zero out the free space to save space in the final image.  Contiguous
  # zeroed space compresses down to nothing.
  dd if=/dev/zero of=/EMPTY bs=1M || echo "dd exit code $? is suppressed"
  rm -f /EMPTY

  # Block until the empty file has been removed, otherwise, Packer
  # will try to kill the box while the disk is still full and that's bad
  sync

  echo "==> Disk usage before cleanup"
  echo "${DISK_USAGE_BEFORE_CLEANUP}"

  echo "==> Disk usage after cleanup"
  df -h
}


# Main
setup_prereqs
setup_users
generate_keys

if [ "$PACKER_BUILDER_TYPE" = "virtualbox-ovf" ]; then
  vagrant_setup
  guest_additions
fi

download_pe
install_agent
setup_git
install_pe
add_pe_users
deploy_code_pe
sleep 15
setup_hiera_pe
run_puppet
run_puppet
run_puppet
add_gitea_webhook
cleanup
free_disk_space

exit 0
