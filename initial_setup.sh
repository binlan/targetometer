#!/bin/bash

if [ $(id -u) -ne 0 ]; then
	echo "Script must be run as root.'"
	exit 1
fi


cd /opt
#git clone https://github.com/akm2b/targetometer.git
git clone https://github.com/binlan/targetometer.git
# patch targetometer
#sed -i 's/\(os.chdir.*\)/#\1/' /opt/targetometer/targetometer.py
aptitude update
aptitude -y install python-smbus python-dev

curl -L -O http://python-distribute.org/distribute_setup.py
python distribute_setup.py
curl -L -O https://raw.github.com/pypa/pip/master/contrib/get-pip.py
python get-pip.py
pip install virtualenv
pip install requests
rm distribute_setup.py get-pip.py

echo 'i2c-bcm2708' >> /etc/modules
echo 'i2c-dev' >> /etc/modules

modprobe i2c-bcm2708
modprobe i2c-dev

# ab hier koennte ich das display benutzen

aptitude -y purge wolfram-engine
aptitude -y safe-upgrade
aptitude -y install cron-apt 
aptitude -y clean

cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
rm -f /etc/profile.d/raspi-config.sh

cat <<\EOF > /opt/targetometer/runme.sh
#!/bin/bash
cd /opt/targetometer/
./targetometer_start.py
EOF
chmod 755 /opt/targetometer/runme.sh

#mv /etc/rc.local /etc/rc.local.orig
cat <<\EOF > /etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

/opt/targetometer/runme.sh &

exit 0
EOF


cat <<\EOF > /etc/cron.d/cron-apt
#
# Regular cron jobs for the cron-apt package
#
# Every night at 4 o'clock.
#0 4     * * *   root    test -x /usr/sbin/cron-apt && /usr/sbin/cron-apt
# Every hour.
# 0 *   * * *   root    test -x /usr/sbin/cron-apt && /usr/sbin/cron-apt /etc/cron-apt/config2
# Every five minutes.
# */5 * * * *   root    test -x /usr/sbin/cron-apt && /usr/sbin/cron-apt /etc/cron-apt/config2

# montag mittag
0 13     * * 1   root    test -x /usr/sbin/cron-apt && /usr/sbin/cron-apt
EOF

cat <<\EOF > /etc/cron.d/targetometer
# taeglich mittag
0 12     * * *   root    test -d /opt/targetometer/ && (cd /opt/targetometer/ ; git pull)
EOF

resize_partition() {
	if ! [ -h /dev/root ]; then
	  echo "/dev/root does not exist or is not a symlink. Don't know how to expand"
	  return 0
	fi
	ROOT_PART=$(readlink /dev/root)
	PART_NUM=${ROOT_PART#mmcblk0p}
	LAST_PART_NUM=$(parted /dev/mmcblk0 -ms unit s p | tail -n 1 | cut -f 1 -d:)
	PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d:)

	if ! [[ "$PART_NUM" -eq 2 || "$LAST_PART_NUM" == "$PART_NUM" || -z "$PART_START" ]] ; then
		echo "dont know, how to resize this disk. i leave it untouched."
		return 0
	fi

	
	fdisk /dev/mmcblk0 <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF

	cat <<\EOF > /etc/init.d/resize2fs_once
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5 S
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "$1" in
  start)
    log_daemon_msg "Starting resize2fs_once" &&
    resize2fs /dev/root &&
    rm /etc/init.d/resize2fs_once &&
    update-rc.d resize2fs_once remove &&
    log_end_msg $?
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF

	chmod +x /etc/init.d/resize2fs_once
	update-rc.d resize2fs_once defaults
}

resize_partition
rm -f /opt/initial_setup.sh
reboot