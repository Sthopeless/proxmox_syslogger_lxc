#!/bin/bash
ps -ef |grep tailon |grep -v grep |awk '{print $2}' | xargs kill
#frontail /var/log/tasmota/* -n 5000 -l 10000 -t dark --ui-highlight -d
#/root/go/bin/tailon "/var/log/tasmota/*.log"
#/root/go/bin/tailon alias=tasmota,/var/log/tasmota/*.log -c /root/config.toml &
/root/tailon alias=tasmota,/var/log/tasmota/*.log -c /root/config.toml &