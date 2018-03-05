# IAM SSH Key Managment for EC2s in AWS

## Tons of credit to Widdix => https://github.com/widdix

### A set of IAM policies and shell script for managing SSH keys centrally in AWS

#### On MASTER AWS IAM account
1. Create a role of the type "Another AWS account", pointing it at the Account ID of the child account. _There must be a unique role for each of the child accounts._ This can be found in the my account menu when logged into the child account.
2. Paste the contents of the _iam-master-policy.json_,replacing the MASTER account ID.
3. Name the policy _iam-master-clientNameHere_

#### On CLIENT AWS IAM account
1. Create an IAM, EC2 role
2. name it _iam-client-clientNameHere_
3. Attach an inline, custom policy with the contents form _iam-child-policy.json_ adding the MASTER Account ID and the MASTER Role name that we just created
4. Attach newly created _client_ role to instance. This can be done via the cli or the AWS EC2 GUI, by highlighting the instance > Instance Settings > Attach/replace IAM role > selecting newly created _client_ role

#### On client EC2
1. sudo git clone https://github.com/giancarlopetrini/aws-iam-ssh.git 
2. cd /opt/aws-iam-ssh/linux-files
3. sudo chmod +x /opt/aws-iam-ssh/linux-files/new-install.sh && sudo chmod +x /opt/aws-iam-ssh/linux-files/new-import-iam-users.sh
4. sudo ./new-install.sh
5. sudo reboot
6. sudo nano /opt/aws-iam-ssh/linux-files/new-import-iam-users.sh
7. change value of IAM info on Line 74, in assume role call, to accurate information, based on the hints
8. sudo /opt/aws-iam-ssh/linux-files/./new-import-iam-users.sh
