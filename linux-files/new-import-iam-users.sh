#!/bin/bash -e

# Special group to mark users as being synced by our script
: ${LOCAL_MARKER_GROUP:="iam-synced-users"}

# Specify a comma seperated list of IAM groups for users who should be given sudo privileges.
# Leave empty to not change sudo access, or give the value '##ALL## to have all users
# be given sudo rights.
: ${SUDOERS_GROUPS:="##ALL##"}
# user add default app
: ${USERADD_PROGRAM:="/usr/sbin/useradd"}
# if needed to leverage other args when creating users
: ${USERADD_ARGS:="--user-group --create-home --shell /bin/bash"}


# Initizalize INSTANCE variable
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')

####primary account sync function####
function sync_accounts() {
    if [ -z "${LOCAL_MARKER_GROUP}" ]
    then
        echo "Please specify a local group to mark imported users. eg iam-synced-users"
        exit 1
    fi

    # Check if local marker group exists, if not, create it
    /usr/bin/getent group "${LOCAL_MARKER_GROUP}" >/dev/null 2>&1 || /usr/sbin/groupadd "${LOCAL_MARKER_GROUP}"

    # define variables
    local iam_users
    local sudo_users
    local local_users
    local intersection
    local removed_users
    local user

    # init group and sudoers from tags
    #get_iam_groups_from_tag
    get_sudoers_groups_from_tag

    iam_users=$(get_clean_iam_users | sort | uniq)
    sudo_users=$(get_clean_sudoers_users | sort | uniq)
    local_users=$(get_local_users | sort | uniq)

    intersection=$(echo ${local_users} ${iam_users} | tr " " "\n" | sort | uniq -D | uniq)
    removed_users=$(echo ${local_users} ${intersection} | tr " " "\n" | sort | uniq -u)

    # Add or update the users found in IAM
    for user in ${iam_users}; do
        if [ "${#user}" -le "32" ]
        then
            create_or_update_local_user "${user}" "$sudo_users"
        else
            echo "Can not import IAM user ${user}. User name is longer than 32 characters."
        fi
    done

    # Remove users no longer in the IAM group(s)
    for user in ${removed_users}; do
        delete_local_user "${user}"
    done
}
###

function log() {
    /usr/bin/logger -i -p auth.info -t aws-ec2-ssh "$@"
}

function setAWSCreds() {
  ##set up environmental variables for connecting via IAM
  stscredentials=$(aws sts assume-role \
      --role-arn arn:aws:iam::<masterIDhere>:role/<masterrolenamehere> \
      --role-session-name pullIAMKeys \
      --query '[Credentials.SessionToken,Credentials.AccessKeyId,Credentials.SecretAccessKey]' \
      --output text)

  AWS_ACCESS_KEY_ID=$(echo "${stscredentials}" | awk '{print $2}')
  AWS_SECRET_ACCESS_KEY=$(echo "${stscredentials}" | awk '{print $3}')
  AWS_SESSION_TOKEN=$(echo "${stscredentials}" | awk '{print $1}')
  AWS_SECURITY_TOKEN=$(echo "${stscredentials}" | awk '{print $1}')
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
}

# Get all IAM users (optionally limited by IAM groups) and assume AWS Role
function get_iam_users() {
  setAWSCreds
##################
  aws iam list-users \
            --query "Users[].[UserName]" \
            --output text \
        | sed "s/\r//g"
}

# Run all found iam users through clean_iam_username
function get_clean_iam_users() {
    local raw_username

    for raw_username in $(get_iam_users); do
        clean_iam_username "${raw_username}" | sed "s/\r//g"
    done
}

# Get previously synced users
function get_local_users() {
    /usr/bin/getent group ${LOCAL_MARKER_GROUP} \
        | cut -d : -f4- \
        | sed "s/,/ /g"
}

# Get list of IAM groups marked with sudo access from tag
function get_sudoers_groups_from_tag() {
    if [ "${SUDOERS_GROUPS_TAG}" ]
    then
        SUDOERS_GROUPS=$(\
            aws --region $REGION ec2 describe-tags \
            --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$SUDOERS_GROUPS_TAG" \
            --query "Tags[0].Value" --output text \
        )
    fi
}

# Get IAM users of the groups marked with sudo access
function get_sudoers_users() {
    local group

    [[ -z "${SUDOERS_GROUPS}" ]] || [[ "${SUDOERS_GROUPS}" == "##ALL##" ]] ||
        for group in $(echo "${SUDOERS_GROUPS}" | tr "," " "); do
            aws iam get-group \
                --group-name "${group}" \
                --query "Users[].[UserName]" \
                --output text
        done
}

# Get the unix usernames of the IAM users within the sudo group
function get_clean_sudoers_users() {
    local raw_username

    for raw_username in $(get_sudoers_users); do
        clean_iam_username "${raw_username}"
    done
}

# Create or update a local user based on info from the IAM group
function create_or_update_local_user() {
    local username
    local sudousers
    local localusergroups

    username="${1}"
    sudousers="${2}"
    localusergroups="${LOCAL_MARKER_GROUP}"

    # check that username contains only alphanumeric, period (.), underscore (_), and hyphen (-) for a safe eval
    if [[ ! "${username}" =~ ^[0-9a-zA-Z\._\-]{1,32}$ ]]
    then
        echo "Local user name ${username} contains illegal characters"
        exit 1
    fi

    if [ ! -z "${LOCAL_GROUPS}" ]
    then
        localusergroups="${LOCAL_GROUPS},${LOCAL_MARKER_GROUP}"
    fi

    if ! id "${username}" >/dev/null 2>&1; then
        ${USERADD_PROGRAM} ${USERADD_ARGS} "${username}"
        /bin/chown -R "${username}:${username}" "$(eval echo ~$username)"
        log "Created new user ${username}"
    fi
    /usr/sbin/usermod -a -G "${localusergroups}" "${username}"

    # Should we add this user to sudo ?
    if [[ ! -z "${SUDOERS_GROUPS}" ]]
    then
        SaveUserFileName=$(echo "${username}" | tr "." " ")
        SaveUserSudoFilePath="/etc/sudoers.d/$SaveUserFileName"
        if [[ "${SUDOERS_GROUPS}" == "##ALL##" ]] || echo "${sudousers}" | grep "^${username}\$" > /dev/null
        then
            echo "${username} ALL=(ALL) NOPASSWD:ALL" > "${SaveUserSudoFilePath}"
        else
            [[ ! -f "${SaveUserSudoFilePath}" ]] || rm "${SaveUserSudoFilePath}"
        fi
    fi
}

function delete_local_user() {
    # First, make sure no new sessions can be started
    /usr/sbin/usermod -L -s /sbin/nologin "${1}" || true
    # ask nicely and give them some time to shutdown
    /usr/bin/pkill -15 -u "${1}" || true
    sleep 5
    # Dont want to close nicely? DIE!
    /usr/bin/pkill -9 -u "${1}" || true
    sleep 1
    # Remove account now that all processes for the user are gone
    /usr/sbin/userdel -f -r "${1}"
    log "Deleted user ${1}"
}

function clean_iam_username() {
    local clean_username="${1}"
    clean_username=${clean_username//"+"/".plus."}
    clean_username=${clean_username//"="/".equal."}
    clean_username=${clean_username//","/".comma."}
    clean_username=${clean_username//"@"/".at."}
    echo "${clean_username}"
}

#call whole sync!!!
sync_accounts

#filter usernames through and grab key files
function get_iam_keys() {
    local_users=$(get_local_users | sort | uniq)
    setAWSCreds
    for user in ${local_users}; do
        if [[ ! -f /home/"${user}"/.ssh/authorized_keys ]]
        then
            mkdir /home/"${user}"/.ssh
            touch /home/"${user}"/.ssh/authorized_keys
        fi
        aws iam list-ssh-public-keys --user-name "${user}" --query "SSHPublicKeys[?Status == 'Active'].[SSHPublicKeyId]" --output text | \
        while read -r KeyId; \
        do
          aws iam get-ssh-public-key --user-name "${user}" --ssh-public-key-id "$KeyId" --encoding SSH --query "SSHPublicKey.SSHPublicKeyBody" --output text \
           >> /home/"${user}"/.ssh/authorized_keys
        done
    done

    #update sshd_config file
    if grep -q "#PubkeyAuthentication" "/etc/ssh/sshd_config"; then
        sed -i "s:#PubkeyAuthentication no:PubkeyAuthentication yes:g" "/etc/ssh/sshd_config"
    fi
    if grep -q "#AuthorizedKeysFile" "/etc/ssh/sshd_config"; then
            sed -i "s:#AuthorizedKeysFile:AuthorizedKeysFile:g" "/etc/ssh/sshd_config"
    fi
    #scrub centos installed user key from AWS to prevent original key access
    #TODO reimplement after testing
    sudo rm -rf /home/centos/.ssh/
    #reload sshd
    service sshd reload
}

#call key retrieval
get_iam_keys
