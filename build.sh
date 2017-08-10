#!/bin/bash
set -x

if [ -z $1 ]; then
  echo "MUST PASS BUILDER, virtualbox-ovf or vmware-vmx! Exiting..."
  exit 1
fi

# Determine if this is a tagged version, or just a commit
GIT_TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || echo 'null')

if [ $GIT_TAG == 'null' ]; then
  export GIT_VERSION=$(git rev-parse --short HEAD)
else
  export GIT_VERSION=$GIT_TAG
fi

LIC_KEY="${LIC_KEY}"
DOWNLOAD_VERSION=${DOWNLOAD_VERSION:-2017.2.2}
DOWNLOAD_DIST=${DOWNLOAD_DIST:-el}
DOWNLOAD_RELEASE=${DOWNLOAD_RELEASE:-7}
DOWNLOAD_ARCH=${DOWNLOAD_ARCH:-x86_64}
DOWNLOAD_RC=${DOWNLOAD_RC:-1}
GIT_VER=$(git rev-parse --short HEAD)
BUILD_VER=${VERSION:-$GIT_VER}
VMX_SOURCE_URL='https://atlas.hashicorp.com/puppetlabs/boxes/centos-7.2-64-nocm/versions/1.0.0/providers/vmware_fusion.box'
OVF_SOURCE_URL='https://atlas.hashicorp.com/puppetlabs/boxes/centos-7.2-64-nocm/versions/1.0.1/providers/virtualbox.box'
GIT_REMOTE=${GIT_REMOTE:-'https://github.com/puppetlabs-seteam/control-repo.git'}

# Setup VMX for import
if [ ! -f '/var/tmp/vmware_fusion/import.vmx' ]; then

  mkdir /var/tmp/import_tmp$$
  mkdir /var/tmp/vmware_fusion

  curl -s -o /var/tmp/import_tmp$$/vmware_fusion.box -L $VMX_SOURCE_URL
  if [ $? -ne 0 ]; then
    echo "Failed to download CentOS Source Box file, exiting!"
    exit 1
  fi

  tar -C /var/tmp/import_tmp$$ -xvf /var/tmp/import_tmp$$/vmware_fusion.box
  if [ $? -ne 0 ]; then
    echo "Failed to gunzip CentOS Source Box file, exiting!"
    exit 2
  fi

  mv /var/tmp/import_tmp$$/* /var/tmp/vmware_fusion/
  if [ $? -ne 0 ]; then
    echo "Failed to copy CentOS Source Box ovf file, exiting!"
    exit 3
  fi

  mv /var/tmp/vmware_fusion/*.vmx /var/tmp/vmware_fusion/import.vmx
  if [ $? -ne 0 ]; then
    echo "Failed to rename CentOS Source vmx file, exiting!"
    exit 4
  fi

fi

# Setup OVF for import
if [ ! -f /var/tmp/import.ovf ]; then

  mkdir /var/tmp/import_tmp$$

  curl -s -o /var/tmp/import_tmp$$/import.box.gz -L $OVF_SOURCE_URL
  if [ $? -ne 0 ]; then
    echo "Failed to download CentOS Source Box file, exiting!"
    exit 5
  fi

  gunzip /var/tmp/import_tmp$$/import.box.gz
  if [ $? -ne 0 ]; then
    echo "Failed to gunzip CentOS Source Box file, exiting!"
    exit 6
  fi

  tar -C /var/tmp/import_tmp$$ -xvf /var/tmp/import_tmp$$/import.box
  if [ $? -ne 0 ]; then
    echo "Failed to extract CentOS Source Box file, exiting!"
    exit 7
  fi

  mv /var/tmp/import_tmp$$/box.ovf /var/tmp/import.ovf
  if [ $? -ne 0 ]; then
    echo "Failed to copy CentOS Source Box ovf file, exiting!"
    exit 8
  fi

  mv /var/tmp/import_tmp$$/*vmdk /var/tmp/
  if [ $? -ne 0 ]; then
    echo "Failed to copy CentOS Source Box vmdk file, exiting!"
    exit 9
  fi

fi

packer build \
  -force \
  -only=$1 \
  -parallel=false \
  -var "GIT_VERSION=$GIT_VERSION" \
  -var "GIT_REMOTE=$GIT_REMOTE" \
  -var "LIC_KEY=$LIC_KEY" \
  -var "BUILD_VER=$BUILD_VER" \
  -var "DOWNLOAD_VERSION=$DOWNLOAD_VERSION" \
  -var "DOWNLOAD_DIST=$DOWNLOAD_DIST" \
  -var "DOWNLOAD_RELEASE=$DOWNLOAD_RELEASE" \
  -var "DOWNLOAD_ARCH=$DOWNLOAD_ARCH" \
  -var "DOWNLOAD_RC=$DOWNLOAD_RC" \
  centos72.json

