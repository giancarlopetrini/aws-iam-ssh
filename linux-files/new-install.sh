#!/bin/bash -e

#install epel-release and update
sudo yum install epel-release -y && sudo yum update
sudo yum install -y python-pip
sudo pip install --upgrade pip
sudo yum install gcc
cd /usr/src
sudo wget https://www.python.org/ftp/python/2.7.10/Python-2.7.10.tgz
tar xzf Python-2.7.10.tgz
cd Python-2.7.10
sudo ./configure
sudo make altinstall
sudo pip install awscli

SSHD_CONFIG_FILE="/etc/ssh/ssh_config"
AUTHORIZED_KEYS_COMMAND_FILE="/opt/aws-iam-ssh/authorized_keys_command.sh"
IMPORT_USERS_SCRIPT_FILE="/opt/aws-iam-ssh/import_users.sh"
MAIN_CONFIG_FILE="/etc/aws-ec2-ssh.conf"

#define variabled
$import_users = "new-import-iam-users.sh"
$import_keys = "new-import-iam-ssh-keys.sh"
#make scrips executable
sudo chmod +x $import_users && sudo chmod +x $import_keys

cat > /etc/cron.d/import_users << EOF
SHELL=/bin/bash
PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/aws/bin
MAILTO=root
HOME=/
*/10 * * * * root $IMPORT_USERS_SCRIPT_FILE
EOF
chmod 0644 /etc/cron.d/import_users



# Restart sshd using an appropriate method based on the currently running init daemon
# Note that systemd can return "running" or "degraded" (If a systemd unit has failed)
# This was observed on the RHEL 7.3 AMI, so it's added for completeness
# systemd is also not standardized in the name of the ssh service, nor in the places
# where the unit files are stored.

# Capture the return code and use that to determine if we have the command available
retval=0
which systemctl > /dev/null 2>&1 || retval=$?

if [[ "$retval" -eq "0" ]]; then
  if [[ (`systemctl is-system-running` =~ running) || (`systemctl is-system-running` =~ degraded) ]]; then
    if [ -f "/usr/lib/systemd/system/sshd.service" ] || [ -f "/lib/systemd/system/sshd.service" ]; then
      systemctl restart sshd.service
    else
      systemctl restart ssh.service
    fi
  fi
elif [[ `/sbin/init --version` =~ upstart ]]; then
    if [ -f "/etc/init.d/sshd" ]; then
      service sshd restart
    else
      service ssh restart
    fi
else
  if [ -f "/etc/init.d/sshd" ]; then
    /etc/init.d/sshd restart
  else
    /etc/init.d/ssh restart
  fi
fi
