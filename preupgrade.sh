#!/bin/sh

ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

echo "<INFO> Stopping services influxdb and telegraf for upgrade."
sudo /bin/systemctl stop influxdb
sudo /bin/systemctl stop telegraf

echo "<INFO> Stopping internal services for upgrade."
pkill -f mqttlive.php > /dev/null 2>&1
pkill -f import_scheduler.pl > /dev/null 2>&1
pkill -f import_loxone.pl> /dev/null 2>&1

echo "<INFO> Creating temporary folders for upgrading"
mkdir -p /tmp/$ARGV1\_upgrade
mkdir -p /tmp/$ARGV1\_upgrade/config
mkdir -p /tmp/$ARGV1\_upgrade/log
mkdir -p /tmp/$ARGV1\_upgrade/data

echo "<INFO> Backing up existing config files"
cp -a $ARGV5/config/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/config

echo "<INFO> Backing up existing log files"
cp -a $ARGV5/log/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/log

echo "<INFO> Backing up existing data files"
cp -a $ARGV5/data/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/data

# Clean up old installation
echo "<INFO> Cleaning old temporary files"
S4LTMP=`jq -r '.stats4lox.s4ltmp' $ARGV5/config/plugins/$ARGV3/stats4lox.json`
rm -fr $S4LTMP

# Exit with Status 0
exit 0
