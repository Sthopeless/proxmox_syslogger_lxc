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
SYSLOGGER_FOLDER="/syslogger/"
mkdir -p $(dirname $SYSLOGGER_FOLDER)
## Crontab
CRONTAB_FILE="/var/spool/cron/crontabs/root"
cat <<EOF >> $CRONTAB_FILE
@reboot /syslogger/frontend.sh
1 0 * * * /syslogger/frontend.sh
12 6 * * * sudo reboot
EOF
## Frontend.sh
FRONTEND_FILE="/syslogger/frontend.sh"
cat <<EOF >> $FRONTEND_FILE
#!/bin/bash
ps -ef |grep tailon |grep -v grep |awk '{print $2}' | xargs kill
/syslogger/tailon alias=tasmota,/var/log/tasmota/*.log -c /syslogger/config.toml &
EOF
## Config.toml
CONFIG_TOML_FILE="/syslogger/config.toml"
cat <<EOF >> $CONFIG_TOML_FILE
title = "Tailon file viewer"
relative-root = "/"
listen-addr = ["0.0.0.0:8080"]
allow-download = true
allow-commands = ["tail", "grep", "sed", "awk"]

[commands]

    [commands.tail]
    action = ["tail", "-n", "$lines", "-F", "$path"]

    [commands.grep]
    stdin = "tail"
    #action = ["grep", "--text", "--line-buffered", "--color=auto", "-i", "$script"]
    action = ["grep", "--text", "--line-buffered", "--color=auto", "-e", "$script"]
    #action = ["grep", "--text", "--line-buffered", "--color=never", "-e", "$script"]
    default = ".*"

    [commands.sed]
    stdin = "tail"
    action = ["sed", "-u", "-e", "$script"]
    default = "s/.*/&/"

    [commands.awk]
    stdin = "tail"
    action = ["awk", "--sandbox", "$script"]
    default = "{print $0; fflush()}"
EOF

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
