#!groovy
import org.yaml.snakeyaml.Yaml

// main
def config = null
def gitCurrent = null
def buildType = null
def description = ''

stage("Setup") {
  node {

    checkout scm

    // Store build configuration in config var (map)
    // keys: download_version (string), ga_release=(bool), pe_dist=(string), pe_release=(int), pe_arch=(string)
    //       git_remote=(string, optional), public_key=(string, optional), priv_key=(string, optional)
    //       publish_images=(bool)
    config = loadConfig(readFile('config/default.yaml')) + loadConfig(readFile('config/build.yaml'))
    config['ga_release'] = config['ga_release'] == true ? 1 : 0

    // Determine if this is a tagged version, or just a commit
    def gitTag =  sh(returnStdout: true, script: 'git describe --exact-match --tags HEAD 2>/dev/null || exit 0').trim()
    def gitVersion = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    gitCurrent = gitTag != '' ? gitTag : gitVersion
    buildType = gitTag != '' ? 'release' : 'commit'

    print "Requested builds for ${config['builds']} using version ${gitCurrent}"
  }
}

stage("Build and Test"){
  def tobuild = [:]
  for ( int i = 0; i < config['builds'].size(); i++ ) {
    def index = i
    tobuild[config['builds'][index]] = {

      node ("tse-master-builder-${config['builds'][index]}") {
        withCredentials(
          [
            file(credentialsId: 'puppetlabs-seteam-jenkins-fog_config', variable: 'fog_config'),
            file(credentialsId: 'puppetlabs-seteam-jenkins-public_key', variable: 'public_key'),
            file(credentialsId: 'puppetlabs-seteam-jenkins-private_key', variable: 'private_key'),
            file(credentialsId: 'puppetlabs-seteam-openstack-script', variable: 'openstack_script'),
            usernamePassword(credentialsId: 'vsphere_userpass', passwordVariable: 'vmware_pass', usernameVariable: 'vmware_user'),
            string(credentialsId: 'puppetlabs-seteam-vmware-vi-string', variable: 'vmware_vi_connection'),
            string(credentialsId: 'puppetlabs-seteam-vmware-datacenter', variable: 'vmware_datacenter'),
          ]
        ){
          pubkey  = readFile public_key
          privkey = readFile private_key

          withEnv([
            'PATH+EXTRA=/usr/local/bin:/Users/jenkins/.rbenv/bin',
            "GIT_REMOTE=${config['git_remote']}",
            "PRIV_KEY=${privkey}",
            "PUB_KEY=${pubkey}",
            "DOWNLOAD_VERSION=${config['download_version']}",
            "DOWNLOAD_DIST=${config['pe_dist']}",
            "DOWNLOAD_RELEASE=${config['pe_release']}",
            "DOWNLOAD_ARCH=${config['pe_arch']}",
            "DOWNLOAD_RC=${config['ga_release']}",
            "GIT_CURRENT=${gitCurrent}",
            "VMWARE_USER=${vmware_user}",
            "VMWARE_PASS=${vmware_pass}",
            "FOG_CONFIG=${fog_config}",
            "OPENSTACK_SCRIPT=${openstack_script}",
            "VMWARE_DS=${config['vmware_datastore']}",
            "VMWARE_NET=${config['vmware_network']}",
            "VMWARE_VI_CONNECTION=${vmware_vi_connection}",
            "VMWARE_DATACENTER=${vmware_datacenter}",
          ]){
            try {
              stage ("Build tse-master-${config['builds'][index]}") {
                checkout scm
                checkout([
                  $class: 'GitSCM',
                  branches: [[name: '*/master']],
                  doGenerateSubmoduleConfigurations: false,
                  extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'util']],
                  submoduleCfg: [],
                  userRemoteConfigs: [[url: 'https://github.com/ipcrm/ovfparser.git']]
                ])

                sh("""
                  set +x
                  source $OPENSTACK_SCRIPT
                  set -x
                  openstack image list
                  exit 1
                """)

                 ansiColor('xterm') {
                   // Virtualbox Build
                   if (config['builds'][index] == 'virtualbox') {
                     sh(script:'./build.sh virtualbox-ovf')

                   } else if (config['builds'][index] == 'vmware') {

                     sh(script:'./build.sh vmware-vmx')

                     // VMWARE: Execute OVFtool to convert VMX
                     sh(script:'''
                       /Applications/VMware\\ OVF\\ Tool/ovftool \
                         --X:logToConsole \
                         --X:logLevel=verbose \
                         --eula='NOT FOR PRODUCTION USE.  DEMO ENVIRONMENT ONLY' \
                         output-vmware-vmx/pe-packer-vmx.vmx \
                         packer-vmware-vmx.ovf
                     ''')

                     // VMWARE: Set Build Info for VMware OVF
                     sh(script:'''
                       ruby util/ovfparser.rb \
                       --filename=packer-vmware-vmx.ovf \
                       --newovfname="pe-vmware-vmx-${GIT_CURRENT}.ovf" \
                       --product="Puppet Enterprise ${DOWNLOAD_VERSION}" \
                       --vendor='Puppet, Inc' \
                       --ovfversion="${GIT_CURRENT}" \
                       --producturl='www.puppet.com' \
                       --vendorurl='www.puppet.com'
                     ''')

                     // VMWARE: Create an OVA file from the VMWare packer artifacts
                     sh(script:'''
                       /Applications/VMware\\ OVF\\ Tool/ovftool \
                         --X:logToConsole \
                         --X:logLevel=verbose \
                         "pe-vmware-vmx-${GIT_CURRENT}.ovf" "tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}.ova"
                     ''')

                  }
                }
              }

              stage ("Test tse-master-${config['builds'][index]}") {
                checkout scm
                ansiColor('xterm') {
                  // Virtualbox Build
                  if (config['builds'][index] == 'virtualbox') {
                    sh(script:'''
                      rbenv global 2.3.1
                      eval "$(rbenv init -)"
                      echo $PATH
                      gem install bundler --version 1.10.6
                      bundle install
                      vagrant box add packer_virtualbox file:"//tse-master-virtualbox-${DOWNLOAD_VERSION}-v${GIT_CURRENT}.box"
                      bundle exec rake beaker:vagrant
                      vagrant box remove packer_virtualbox
                    ''')
                  } else if (config['builds'][index] == 'vmware') {

                    // VMWARE: Put Fog config in place
                    sh(returnStatus: true, script:"""
                      cat $FOG_CONFIG > fog
                    """)

                    // VMWare Build
                     sh(script:"""
                       # VMWARE: Acceptance Testing, Start by uploading OVF
                       /Applications/VMware\\ OVF\\ Tool/ovftool \
                         --noSSLVerify       \
                         --skipManifestCheck \
                         --acceptAllEulas    \
                         -ds=\"${VMWARE_DS}\"   \
                         --net:\"nat\"=\"${VMWARE_NET}\" \
                         "tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}.ova" \
                         "vi://${VMWARE_USER}:${VMWARE_PASS}@${VMWARE_VI_CONNECTION}"
                     """)

                     sh(script:"""
                       rbenv global 2.3.1
                       eval "\$(rbenv init -)"
                       gem install bundler --version 1.10.6
                       bundle install
                       BEAKER_vcloud_template="tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}" bundle exec rake beaker:vmware
                     """)

                    // VMWARE: Clean-Up Template
                    sh(script:"""
                      rbenv global 2.3.1
                      eval "\$(rbenv init -)"
                      gem install bundler --version 1.10.6
                      bundle install
                      datacenter=\"${VMWARE_DATACENTER}\" fog_config=fog \
                        vm_name=\"tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}\" \
                        bundle exec ruby scripts/remove_vm.rb
                      rm -f fog
                    """)

                  }

                }
              }

              stage ("Upload"){
                sh 'mkdir commits releases'

                if (buildType == 'commit') {
                  sh 'find . -name "*.box" -o -name "*.ova" | xargs -I {} mv {} commits/'
                } else if (buildType == 'release') {
                  sh 'find . -name "*.box" -o -name "*.ova" | xargs -I {} mv {} releases/'
                }

                if (config['publish_images'] != false) {
                  sh("""
                    source $OPENSTACK_SCRIPT
                    openstack image create \
                      --disk-format vmdk \
                      --file *.vmdk \
                      "tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}"
                  """)

                  step([$class: 'S3BucketPublisher',
                    consoleLogLevel: 'INFO',
                    dontWaitForConcurrentBuildCompletion: false,
                    entries: [
                      [
                        bucket: 'tse-builds/tse-demo-env',
                        excludedFile: '',
                        flatten: false,
                        gzipFiles: false,
                        keepForever: true,
                        managedArtifacts: false,
                        noUploadOnFailure: true,
                        selectedRegion: 'us-west-2',
                        showDirectlyInBrowser: false,
                        sourceFile: '*/*.ova',
                        storageClass: 'STANDARD',
                        uploadFromSlave: false,
                        useServerSideEncryption: false
                      ],
                      [
                        bucket: 'tse-builds/tse-demo-env',
                        excludedFile: '',
                        flatten: false,
                        gzipFiles: false,
                        keepForever: true,
                        managedArtifacts: false,
                        noUploadOnFailure: true,
                        selectedRegion: 'us-west-2',
                        showDirectlyInBrowser: false,
                        sourceFile: '*/*.box',
                        storageClass: 'STANDARD',
                        uploadFromSlave: false,
                        useServerSideEncryption: false]
                    ],
                    pluginFailureResultConstraint: 'FAILURE',
                    profileName: 'tse-jenkins',
                    userMetadata: []
                  ])

                }

              }

              stage ("Cleanup") {
                step([$class: 'WsCleanup'])
              }

            } catch (error) {
              stage("Failure Cleanup") {
                step([$class: 'WsCleanup'])
                description = description + "Build ${config['builds'][index]} failed.  No artifacts for ${config['builds'][index]} uploaded."

                //Cleanup any deployed artifacts
                if (config['builds'][index] == 'virtualbox') {

                  sh(returnStatus: true, script:'vagrant box remove packer_virtualbox')

                } else if (config['builds'][index] == 'vmware') {

                  sh(returnStatus: true, script:"""
                    rbenv global 2.3.1
                    eval "\$(rbenv init -)"
                    gem install bundler --version 1.10.6
                    bundle install
                    datacenter=\"${VMWARE_DATACENTER}\" fog_config=fog \
                      vm_name=\"tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}\" \
                      bundle exec ruby scripts/remove_vm.rb
                    rm -f fog
                  """)

                }

                // Fail
                throw error
              }
            }
          }
        }
      }
    }
  }
  parallel tobuild
}

// Set Build info
description = description == '' ? 'Build Successful.' : description
description = description + "\nArtifact location <a href=\"http://tse-builds.s3-website-us-west-2.amazonaws.com/tse-demo-env/${buildType}s\">here</a>."
currentBuild.description = description

// functions
def loadConfig(def yaml){
  new Yaml().load(yaml)
}
