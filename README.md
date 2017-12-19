# aws-iam-ssh  

## Tons of credit to Widdix => https://github.com/widdix

### A set of IAM policies and shell script for managing SSH keys centrally in AWS

#### On MASTER AWS IAM account
1. Create a role of the type "Another AWS account", pointing it at the Account ID of the child account. _There must be a unique policy for each of the child accounts._ This can be found in the my account menu when logged into the child account.
2. Paste the contents of the _iam-master-policy.json_,replacing the MASTER account ID.
3. Name the policy _iam-master-clientNameHere_

#### On CLIENT AWS IAM account
1. Create an IAM, EC2 role
2. name it _iam-client-clientNameHere_
3. Attach an inline, custom policy with the contents form _iam-child-policy.json_ adding the MASTER Account ID and the MASTER Role name that we just created
4. Attach newly created _client_ role to instance

#### On newly created EC2
1. git clone https://github.com/giancarlopetrini/aws-iam-ssh.git /opt/aws-iam-ssh
2. cd /opt/aws-iam-ssh && chmod +x new-import-iam-users.sh
3. ./new-import-iam-users.sh
