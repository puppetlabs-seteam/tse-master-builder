#!groovy
import org.yaml.snakeyaml.Yaml

// main
def config = [:]
def gitCurrent = null
def buildType = null
def description = ''

stage("Setup") {
  node {

    git branch: env.BUILD_BRANCH, changelog: false, poll: false, url: 'https://github.com/puppetlabs-seteam/tse-master-builder.git'

    // Store build configuration in config var (map)
    // keys: download_version (string), ga_release=(bool), pe_dist=(string), pe_release=(int), pe_arch=(string)
    //       git_remote=(string, optional), public_key=(string, optional), priv_key=(string, optional)
    //       publish_images=(bool)
    config['download_version'] = env.DOWNLOAD_VERSION
    config['vmware_datastore'] = env.VMWARE_DATASTORE
    config['vmware_network'] = env.VMWARE_NETWORK
    config['publish_images'] = env.PUBLISH_IMAGES.toBoolean() == true ? 1 : 0
    config['build_version'] = env.BUILD_VERSION
    config['build_notice'] = env.BUILD_NOTICE
    config['ga_release'] = env.GA_RELEASE.toBoolean() == true ? 1 : 0
    config['pe_release'] = env.DIST_RELEASE.toInteger()
    config['git_remote'] = env.GIT_REMOTE
    config['public_key'] = env.PUBLIC_KEY
    config['priv_key']   = env.PRIV_KEY
    config['pe_dist']    = env.PE_DIST
    config['pe_arch']    = env.PE_ARCH
    config['builds']     = env.BUILDS.split(',')

    if (!config['build_version']?.trim()) {
      error("FAILED - BUILD_VERSION parameter cannot be left empty!")
    }

    // Determine if this is a tagged version, or just a commit (this gets read from the control-repo)
    dir ('control-repo') {
      git branch: 'production', changelog: false, poll: false, url: env.GIT_REMOTE
      sh("git reset --hard ${config['build_version']}")
      def gitTag =  sh(returnStdout: true, script: 'git describe --exact-match --tags HEAD 2>/dev/null || exit 0').trim()
      def gitVersion = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
      gitCurrent = gitTag != '' ? gitTag : gitVersion
      buildType = gitTag != '' ? 'release' : 'commit'
      changelog = sh(returnStdout: true, script: "git log --no-color --pretty=format:\"%h %ad | %s%d [%an]%n   %b%n\" --graph --notes --date=short \$(git describe --abbrev=0 --tags ${config['build_version']}^)..${config['build_version']}")

    }

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
            file(credentialsId: 'puppetlabs-seteam-license_key', variable: 'license_key'),
            file(credentialsId: 'puppetlabs-seteam-openstack-script', variable: 'openstack_script'),
            usernamePassword(credentialsId: 'vsphere_userpass', passwordVariable: 'vmware_pass', usernameVariable: 'vmware_user'),
            string(credentialsId: 'puppetlabs-seteam-vmware-vi-string', variable: 'vmware_vi_connection'),
            string(credentialsId: 'puppetlabs-seteam-vmware-datacenter', variable: 'vmware_datacenter'),
          ]
        ){
          license = readFile license_key

          // Need to store a version of vars without dots
          download_version_dash = config['download_version'].replace('.','')
          git_current = gitCurrent.replace('.','-')

          withEnv([
            'PATH+EXTRA=/usr/local/bin:/Users/jenkins/.rbenv/bin',
            "GIT_REMOTE=${config['git_remote']}",
            "DOWNLOAD_VERSION=${config['download_version']}",
            "DWNLD_VER=${download_version_dash}",
            "DOWNLOAD_DIST=${config['pe_dist']}",
            "DOWNLOAD_RELEASE=${config['pe_release']}",
            "DOWNLOAD_ARCH=${config['pe_arch']}",
            "DOWNLOAD_RC=${config['ga_release']}",
            "GIT_CURRENT=${gitCurrent}",
            "GIT_CUR=${git_current}",
            "VMWARE_USER=${vmware_user}",
            "VMWARE_PASS=${vmware_pass}",
            "FOG_CONFIG=${fog_config}",
            "LIC_KEY=${license}",
            "OPENSTACK_SCRIPT=${openstack_script}",
            "VMWARE_DS=${config['vmware_datastore']}",
            "VMWARE_NET=${config['vmware_network']}",
            "VMWARE_VI_CONNECTION=${vmware_vi_connection}",
            "VMWARE_DATACENTER=${vmware_datacenter}",
          ]){
            try {
              stage ("Build tse-master-${config['builds'][index]}") {
                git branch: env.BUILD_BRANCH, changelog: false, poll: false, url: 'https://github.com/puppetlabs-seteam/tse-master-builder.git'
                checkout([
                  $class: 'GitSCM',
                  branches: [[name: '*/master']],
                  doGenerateSubmoduleConfigurations: false,
                  extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'util']],
                  submoduleCfg: [],
                  userRemoteConfigs: [[url: 'https://github.com/ipcrm/ovfparser.git']]
                ])

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
                git branch: env.BUILD_BRANCH, changelog: false, poll: false, url: 'https://github.com/puppetlabs-seteam/tse-master-builder.git'
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
                         -vf="cs-general/tse/home" \
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
                        vm_name=\"cs-general/tse/home/tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}\" \
                        bundle exec ruby scripts/remove_vm.rb
                      rm -f fog
                    """)

                  }

                }
              }

              stage ("Upload"){
                sh 'mkdir commits releases branches'

                // Set Target
                if (env.BUILD_BRANCH != 'master') {
                  target = 'branches'
                } else if (buildType == 'commit') {
                  target = 'commits'
                } else if (buildType == 'release') {
                  target = 'releases'
                }

                // Move Archive
                sh "find . -name \"*.box\" -o -name \"*.ova\" | xargs -I {} mv {} ${target}/"

                if (config['publish_images'] == 1) {

                  if (config['builds'][index] == 'virtualbox') {
                    sh("""
                      set +x
                      source $OPENSTACK_SCRIPT
                      set -x

                      openstack image create \
                        --disk-format vmdk \
                        --file output-virtualbox-ovf/*.vmdk \
                        "tse-master-${DWNLD_VER}-v${GIT_CUR}"
                    """)
                  }

                  // Only Upload to S3 if this is GA (RCs get uploaded to SLICE)
                  if ( config['ga_release'] == 1 ) {

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
                      vm_name=\"cs-general/tse/home/tse-master-vmware-${DOWNLOAD_VERSION}-v${GIT_CURRENT}\" \
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

//Notify - Only on master, ie stable, tse-master-builder builds
if (env.BUILD_BRANCH == 'master' &&  buildType == 'release') {
  emailext body: "New Release has been published!  Version: PE ${config['download_version']} @ ${config['build_version']}\nArtifact location: http://tse-builds.s3-website-us-west-2.amazonaws.com/tse-demo-env/${buildType}s\nDocs: https://confluence.puppetlabs.com/display/TSE/Demo+Env+Reboot\n\nChanges:\n${changelog}", subject: "[SE Demo Environment] - New Release! (PE ${config['download_version']} @ ${config['build_version']})", to: "${config['build_notice']}", replyTo: 'noreply@puppet.com'
}

// functions
def loadConfig(def yaml){
  new Yaml().load(yaml)
}
