#!/usr/bin/env bash

# Setup script environment
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap 'die "Script interrupted."' INT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

# Prepare container OS
msg "Setting up container OS..."
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
apt-get -y purge openssh-{client,server} >/dev/null
apt-get autoremove >/dev/null

# Update container OS
msg "Updating container OS..."
apt-get update >/dev/null
apt-get -qqy upgrade &>/dev/null

# Install prerequisites
msg "Installing prerequisites..."
apt-get -qqy install \
    curl &>/dev/null

## Instaling Python3-pip and Tailon
msg "Instaling Python3-pip & Tailon"
apt-get -qqy install python3-pip &>/dev/null
pip3 install -q tailon

## Configuring
msg "Configuring Folders"
SYSLOGGER_FOLDER="/syslogger"
TAR_FILE="/syslogger/syslogger.tar.gz"
FRONTEND_FILE="/syslogger/frontend.sh"
CONFIG_TOML_FILE="/syslogger/config.toml"
SYSLOG_FILE="/syslogger/syslog"
TAILON_FILE="/syslogger/tailon"
CRONTAB_BEFORE="/syslogger/crontab"
CRONTAB_AFTER="/var/spool/cron/crontabs/root"
SYSLOGLOCNEW="/etc/rsyslog.conf"
SYSLOGLOCOLD="/syslogger/rsyslog.conf"

mkdir -p $(dirname $SYSLOGGER_FOLDER)
mkdir -p $(dirname $TAR_FILE)
mkdir -p $(dirname $CONFIG_TOML_FILE)
mkdir -p $(dirname $CRONTAB_BEFORE)

msg "Downloading last dependencies"
wget -q https://github.com/Sthopeless/proxmox_syslogger_lxc/raw/main/syslogger.tar.gz -O $TAR_FILE

cd $SYSLOGGER_FOLDER; tar -xvf $TAR_FILE &>/dev/null
chmod 755 $FRONTEND_FILE $TAILON_FILE

mv $CRONTAB_BEFORE $CRONTAB_AFTER
mv $SYSLOGLOCOLD $SYSLOGLOCNEW

chown -R root:crontab $CRONTAB_AFTER

# Customize container
msg "Customizing container..."
rm /etc/motd # Remove message of the day after login
rm /etc/update-motd.d/10-uname # Remove kernel information after login
touch ~/.hushlogin # Remove 'Last login: ' and mail notification after login
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')

# Cleanup container
msg "Cleanup..."
rm -rf /setup.sh /var/{cache,log}/* /var/lib/apt/lists/*
