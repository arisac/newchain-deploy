#!/bin/bash

set -eu

# Use this script to download the latest NewChain release binary.
# Use USE_NEWCHAIN_VERSION to specify a specific release version.
#   Example: USE_NEWCHAIN_VERSION=v1.8.26 ./newchain.sh

newchain_deploy_latest_version='v1.2.2-f1b3400'
default_networkname='mainnet'

function color() {
    # Usage: color "31;5" "string"
    # Some valid values for color:
    # - 5 blink, 1 strong, 4 underlined
    # - fg: 31 red,  32 green, 33 yellow, 34 blue, 35 purple, 36 cyan, 37 white
    # - bg: 40 black, 41 red, 44 blue, 45 purple
    printf '\033[%sm%s\033[0m\n' "$@"
}
color "37" ""

system=""
case "$OSTYPE" in
darwin*) system="darwin" ;;
linux*) system="linux" ;;
msys*) system="windows" ;;
cygwin*) system="windows" ;;
*) exit 1 ;;
esac
readonly system

if [ "$system" != "linux" ]; then
    color "31" "Not support's system, please use Ubuntu 18.04 LTS."
    exit 1
fi
color "37" "Current system is $system"

# Check run as root
if [ $EUID -ne 0 ]; then
   color "31" "Run this script with 'sudo $0'"
   exit 1
fi

# get current user
sudo_user="$SUDO_USER"
if [ "$sudo_user" == "" ]; then
  sudo_user="$(whoami)"
fi

color "33" "Current sudo user is $sudo_user"

if [[ "$*" == "" ]]; then
  networkname="${default_networkname}"
elif [[ "$*" == "mainnet" || "$*" == "main" ]]; then
  networkname="mainnet"
elif [[ "$*" == "testnet" || "$*" == "test" ]]; then
  networkname="testnet"
else
  color "31" "Not support network $*."
  exit 1
fi
color "32" "Current NewChain network is ${networkname}"


download_rooturl="https://release.cloud.diynova.com"


################## work directory ##################
color "37" "Trying to init the work directory..."
mkdir -p /data/newchain/${networkname}/bin/
chown -R $sudo_user /data/newchain
# check running
if [ "$(supervisorctl status newchain | awk '{print $2}')" == "RUNNING" ]; then
  supervisorctl stop newchain
fi
if [ "$(supervisorctl status newchainguard | awk '{print $2}')" == "RUNNING" ]; then
  supervisorctl stop newchainguard
fi

color "" "################## NewChain ##################"
function get_newchain_version() {
    if [[ -n ${USE_NEWCHAIN_VERSION:-} ]]; then
        readonly reason="specified in \$USE_NEWCHAIN_VERSION"
        readonly newchain_version="${USE_NEWCHAIN_VERSION}"
    else
        # Find the latest NewChain version available for download.
        readonly reason="automatically selected latest available version"
        newchain_version_url="${download_rooturl}/newton/newchain/latest.txt"
        if [[ "$networkname" == "testnet" ]]; then
          newchain_version_url="${download_rooturl}/newton/newchain/latest-testnet.txt"
        fi
        color '' "Trying get newchain version from url $newchain_version_url"
        newchain_version=$(curl -f -s "${newchain_version_url}") || (color "31" "Get NewChain latest version error." && exit 1)
        readonly newchain_version
    fi
}

get_newchain_version
color "37" "Latest NewChain version is $newchain_version."

newchian_network_file="geth.${newchain_version}"

if [[ -f /data/newchain/${networkname}/bin/${newchian_network_file} ]]; then
    color "32" "NewChain is up to date."
    if [[ "$(realpath /data/newchain/${networkname}/bin/geth)" != "/data/newchain/${networkname}/bin/${newchian_network_file}" ]]; then
      ln -sf "${newchian_network_file}" /data/newchain/${networkname}/bin/geth
      color "37" "Updated NewChain binary link."
      supervisorctl restart newchain || {
        color "31" "Failed to restart newchain by supervisor."
        exit 1
      }
    fi
    # exit 0 # not now
fi

file="geth"
function download_geth_bin() {
  color "34" "Downloading NewChain binary@${newchain_version} to ${file} (${reason})"
  color "33" "${download_rooturl}/newton/newchain/${newchain_version}/${system}/${file}"
  curl -L "${download_rooturl}/newton/newchain/${newchain_version}/${system}/${file}" -o $file || {
    color "31" "Failed to download the NewChain binary."
    exit 1
  }
}

curl --silent -L "${download_rooturl}/newton/newchain/${newchain_version}/${system}/${file}.sha256" -o "${file}.sha256"
#curl --silent -L "${download_rooturl}/newton/newchain/${newchain_version}/${system}/${file}.sig" -o "${file}.sig"
# TODO: add gpg
if test -f "$file"; then
  sha256sum_res=$(shasum -a 256 -c "${file}.sha256" | awk '{print $2}')
  if [ "$sha256sum_res" == "OK" ]; then
      color "32" "Verify $file $sha256sum_res, checksum match."
  else
    download_geth_bin
  fi
else
  download_geth_bin
fi

color "37" "Trying to verify the downloaded NewChain binary file..."
sha256sum_res=$(shasum -a 256 -c "${file}.sha256" | awk '{print $2}')
if [ "$sha256sum_res" == "OK" ]; then
  color "32" "Verify $file $sha256sum_res, checksum match."
else
  color "41" "Verify $file $sha256sum_res, checksum did NOT match."
  exit 1
fi

chmod +x $file
cp $file /data/newchain/${networkname}/bin/${newchian_network_file}
ln -sf "${newchian_network_file}" /data/newchain/${networkname}/bin/geth || {
  color "31" "Failed to link geth to $newchian_network_file."
  exit 1
}
color "37" "Updated NewChain binary link."

################## NewChain Guard ##################
color "" "################## NewChain Guard ##################"
# install newchain guard
function get_newchain_guard_version() {
    if [[ -n ${USE_NEWCHAIN_GUARD_VERSION:-} ]]; then
        readonly guard_reason="specified in \$USE_NEWCHAIN_GUARD_VERSION"
        readonly newchain_guard_version="${USE_NEWCHAIN_GUARD_VERSION}"
    else
        # Find the latest NewChain Guard version available for download.
        readonly guard_reason="automatically selected latest available version"
        newchain_guard_version_url="${download_rooturl}/newton/NewChainGuard/latest.txt"
        color '' "Trying get newchain guard version from url $newchain_guard_version_url"
        newchain_guard_version=$(curl -f -s "${newchain_guard_version_url}") || (color "31" "Get NewChain Guard latest version error." && exit 1)
        readonly newchain_guard_version
    fi
}

get_newchain_guard_version
color "37" "Latest NewChain Guard version is ${newchain_guard_version}."

newchian_guard_network_file="guard.${newchain_guard_version}"
if [[ -f /data/newchain/${networkname}/bin/${newchian_guard_network_file} ]]; then
    color "32" "NewChain Guard is up to date."
    if [[ "$(realpath /data/newchain/${networkname}/bin/guard)" != "/data/newchain/${networkname}/bin/${newchian_guard_network_file}" ]]; then
      ln -sf "${newchian_guard_network_file}" /data/newchain/${networkname}/bin/guard
      color "37" "Updated NewChain Guard binary link."
      # supervisorctl restart newchainguard || {
      #   color "31" "Failed to restart newchain guard by supervisor."
      #   exit 1
      # }
    fi

    # exit 0 # not now
fi

guard_file="NewChainGuard"
function download_guard_bin() {
  color "34" "Downloading NewChainGuard@${newchain_guard_version} binary to ${guard_file}"
  color "33" "${download_rooturl}/newton/NewChainGuard/${newchain_guard_version}/${system}/${guard_file}"
  curl -L "${download_rooturl}/newton/NewChainGuard/${newchain_guard_version}/${system}/${guard_file}" -o $guard_file || {
    color "31" "Failed to download the NewChain Guard binary."
    exit 1
  }
}

curl --silent -L "${download_rooturl}/newton/NewChainGuard/${newchain_guard_version}/${system}/${guard_file}.sha256" -o "${guard_file}.sha256"
if test -f "$guard_file"; then
  sha256sum_res=$(shasum -a 256 -c "${guard_file}.sha256" | awk '{print $2}')
  if [ "$sha256sum_res" == "OK" ]; then
      color "32" "Verify $file $sha256sum_res, checksum match."
  else
    download_guard_bin
  fi
else
  download_guard_bin
fi


color "37" "Trying to verify the downloaded NewChain Guard binary file..."
sha256sum_res=$(shasum -a 256 -c "${guard_file}.sha256" | awk '{print $2}')
if [ "$sha256sum_res" == "OK" ]; then
  color "32" "Verify $guard_file $sha256sum_res, checksum match."
else
  color "41" "Verify $guard_file $sha256sum_res, checksum did NOT match."
  exit 1
fi

chmod +x $guard_file
cp $guard_file /data/newchain/${networkname}/bin/${newchian_guard_network_file}
ln -sf "${newchian_guard_network_file}" /data/newchain/${networkname}/bin/guard || {
  color "31" "Failed to link $newchian_guard_network_file to guard."
  exit 1
}
color "37" "Updated NewChain Guard binary link."

################## deploy files ##################
# NewChain Deploy file
color "" "################## deploy config files ##################"
if [[ ! -x /data/newchain/conf/node.toml ]]; then
  newchain_network_deploy_file="newchain-${networkname}-$newchain_deploy_latest_version.tar.gz"

  if [[ ! -x $newchain_network_deploy_file ]]; then
      color "34" "Downloading NewChain installation package@${newchain_network_deploy_file} to ${newchain_network_deploy_file}"
      color "33" "${download_rooturl}/newton/newchain-deploy/${networkname}/${newchain_network_deploy_file}"
      curl -L "${download_rooturl}/newton/newchain-deploy/${networkname}/${newchain_network_deploy_file}" -o $newchain_network_deploy_file || {
        color "31" "Failed to download the NewChain installation package."
        exit 1
      }
      curl --silent -L "${download_rooturl}/newton/newchain-deploy/${networkname}/${newchain_network_deploy_file}.sha256" -o "${newchain_network_deploy_file}.sha256"
      chmod +x $newchain_network_deploy_file
  else
      color "37" "NewChain installation package is up to date."
  fi

  color "37" "Trying to verify the downloaded installation file..."
  # TODO: add gpg
  sha256sum_deploy_res=$(shasum -a 256 -c "${newchain_network_deploy_file}.sha256" | awk '{print $2}')
  if [ "$sha256sum_deploy_res" == "OK" ]; then
      color "32" "Verify $newchain_network_deploy_file $sha256sum_deploy_res, checksum match."
  else
      color "41" "Verify $newchain_network_deploy_file $sha256sum_deploy_res, checksum did NOT match."
      exit 1
  fi

  tar zxf "$newchain_network_deploy_file" -C /data/newchain  || {
    color "31" "Failed to extract $newchain_network_deploy_file to /data/newchain."
    exit 1
  }
  chown -R $sudo_user /data/newchain
  sed -i "s/run_as_username/$sudo_user/g" /data/newchain/${networkname}/conf/node.toml
fi

if [[ ! -x /data/newchain/${networkname}/nodedata/geth/ ]]; then
  color "37" "Trying to init the NewChain node data directory..."
  /data/newchain/${networkname}/bin/geth --config /data/newchain/${networkname}/conf/node.toml --datadir /data/newchain/${networkname}/nodedata init /data/newchain/${networkname}/share/newchain${networkname}.json  || {
    color "31" "Failed to init the NewChain node data directory."
    exit 1
  }
else
  # force re-init nodedata
  color "37" "Trying to re-init the NewChain node data directory..."
  /data/newchain/${networkname}/bin/geth --config /data/newchain/${networkname}/conf/node.toml --datadir /data/newchain/${networkname}/nodedata init /data/newchain/${networkname}/share/newchain${networkname}.json  || {
    color "31" "Failed to init the NewChain node data directory."
    exit 1
  }
fi

chown -R $sudo_user:$sudo_user /data/newchain/${networkname}

color "37" "Trying to check and configure supervisor..."
type supervisorctl &> /dev/null || (apt update && apt install -y supervisor) || {
  color "31" "Failed to install supervisor."
  exit 1
}

sed -i "s/run_as_username/$sudo_user/g" /data/newchain/${networkname}/supervisor/newchain.conf || {
  color "31" "Failed to update newchain supervisor config file."
  exit 1
}
cp /data/newchain/${networkname}/supervisor/newchain.conf /etc/supervisor/conf.d/ || {
  color "31" "Failed to copy newchain supervisor config file."
  exit 1
}

sed -i "s/run_as_username/$sudo_user/g" /data/newchain/${networkname}/supervisor/newchainguard.conf || {
  color "31" "Failed to update newchain supervisor config file."
  exit 1
}
cp /data/newchain/${networkname}/supervisor/newchainguard.conf /etc/supervisor/conf.d/ || {
  color "31" "Failed to copy newchain supervisor config file."
  exit 1
}

supervisorctl update || {
  color "31" "Failed to exec supervisorctl update."
  exit 1
}

# force sleep 3s, waiting newchain and guard to be stared
sleep 3


LOGO=$(
      cat <<-END

NNNNNNNNNNNNNNNNNNWX0xoc;'...        ...';cox0XWNNNNNNNNNNNNNNNNNN
NNNNNNNNNNNNNNWNOd:'....,:coddxxxxxxddoc:,....':dONWNNNNNNNNNNNNNN
NNNNNNNNNNNNXkl,...;lxOXNWNNNNNNNNNNNNNNWNXOxl;...,lkXWNNNNNNNNNNN
NNNNNNNNNWKo,..'cxKWNNNNNNNNNNNNNewtonNNNNNNNNNKxc'..,oKWNNNNNNNNN
NNNNNNNW0l. .:xXWNNNNNNNNNNNNNNNNewChainNNNNNNNNNNNWXx:. .l0WNNNNN
NNNNNNKo. .c0WNNNNNNNNNNNNNNNNNNNWWNNNNNNNNWNWNNNNNNWOc. .oKWNNNNN
NNNNNk,..:OWNNNNNNNNNNNNNNNNXkl,:d0NNNNNW0d:,dNNNNNNNNWO:. ,kWNNNN
NNNXo. 'xNNNNNNNNNNNNNNNNNNx,..:dOXNNNNKl..,lOWNNNNNNNNNNx' .oNNNN
NNXl. ;0WNNNNNNNNNNNNNNNNWd..:0WNNNNNNK: .dXNNNNNNNNNNNNNW0; .lXNN
NXl. :KNNNNNNNNNNNNNNNNNN0, ;KNNNNNNNWd..dWNNNNNNNNNNNNNNNNK: .lXN
No. ;0NNNNNNNNNNNNNNNNNNNO' cXWWWWWWWNl .kNNNNNNNNNNNNNNNNNN0; .dW
O' 'kWNNNNNNNNNNNNWXKOkxd:. .:::::::::. .:oxkOKXWNNNNNNNNNNNWk. 'O
c .lNNNNNNNNNWKkoc;'....'.. .:ccccccc:. ..'....';cokKNNNNNNNNNl..c
' 'ONNNNNNW0o;...,coxO0XXk. cNNNNNNNNNl .xXX0Oxoc;...;o0WNNNNNO' '
. ;XNNNNW0c..,okKNNNNNNNNO. cNNNNNNNNNl..kNNNNNNNNKko,..c0WNNNK; .
  cNNNNNK; 'xNNNNNNNNNNNNO. cNNNNNNNNNl .ONNNNNNNNNNNNx' ;0NNNNc
  lNNNNNO' :KNNNNNNNNNNNNO. cNNNNNNNNWl .kNNNNNNNNNNNNX: .ONNNNl
  :XNNNNNo..;xKWNNNNNNNNNO. cNNNNNNNNWl .ONNNNNNNNNWKx;..oNNNNXc
. ,0NNNNNWOc'..;ox0XNWNNNO' cNNNNNNNNNl .kNNNWNX0xo:...cOWNNNN0, .
; .xWNNNNNNWXkl;'...,:codc. ;k0000000k: .cdoc:,...';lkXWNNNNNWx. ;
d. ;KNNNNNNNNNNWX0kdl:;,'.  ...........  .',;:ldk0XWNNNNNNNNNK; .d
X: .oNNNNNNNNNNNNNNNNWWNXx. ;kOOOkkOOk: .dXNWNNNNNNNNNNNNNNNNo. :X
NO, .dNNNNNNNNNNNNNNNNNNNk. lNNNNNNNNNc 'ONNNNNNNNNNNNNNNNNWd. ,ON
NWk' .dNNNNNNNNNNNNNNNNNXc..xWNNNNNNWk' :XNNNNNNNNNNNNNNNNNd. 'kWN
NNWO, .lXNNNNNNNNNNNNNKx,..dNNNNWWXOl..;0NNNNNNNNNNNNNNNNXl. ,OWNN
NNNW0:..;kWNNNNNNNNNNd..'l0WNNNNKx:..;dXNNNNNNNNNNNNNNNWO;..:0WNNN
NNNNNNd' .c0WNNNNNNNW0xkXWNNNNNNNKkx0NNNNNNNNNNNNNNNNW0c. 'dXNNNNN
NNNNNNWKl. .cONNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNOc. .lKWNNNNNN
NNNNNNNNW0l'..,o0NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN0o;..'l0WNNNNNNNN
NNNNNNNNNNWKx:. .,lkKNWNNNNNNNNNNNNNNNNNNNNWNKkl,. .:xKWNNNNNNNNNN
NNNNNNNNNNNNNW0d:'...,coxO0KXNNWWWWNNXK0Oxo:,...':d0WNNNNNNNNNNNNN
NNNNNNNNNNNNNNNNWXOdc;......',,;;;;,,'......;cdOXWNNNNNNNNNNNNNNNN
NNNNNNNNNNNNNNNNNNNNWN0xo:,...      ...,:ok0NWNNNNNNNNNNNNNNNNNNNN
END
  )

color "32" "NewChain ${networkname} has been SUCCESSFULLY deployed!"
color "32" "$LOGO"
