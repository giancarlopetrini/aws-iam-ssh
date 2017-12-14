#!/bin/bash -e

#grab key files
aws iam list-ssh-public-keys --user-name "giancarlo" --query "SSHPublicKeys[?Status == 'Active'].[SSHPublicKeyId]" --output text | while read -r KeyId; \
do
  aws iam get-ssh-public-key --user-name "giancarlo" --ssh-public-key-id "$KeyId" --encoding SSH --query "SSHPublicKey.SSHPublicKeyBody" --output text \
   >> test.txt
done
