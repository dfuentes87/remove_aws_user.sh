#!/bin/bash

#### This script will remove an IAM user from the default AWS account ####

# Based on work by Varun Chandak (https://vrnchndk.in/); modified by David Fuentes (http://github.com/dfuentes87)
# Steps are in accordance with procedures set by AWS IAM documentation:
# https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_manage.html#id_users_deleting

# location of aws bin
alias aws='$(which aws) --output text'
shopt -s expand_aliases
# set the user supplied arguement as the username
USER_NAME="$1"

# no arguements show usage info; also check if the user exists, confirming removal
if [[ $# -eq 0 ]]; then
  echo 'Usage: remove_aws_user.sh "USERNAME"

  Note: The username should not contain any special characters (except hyphen)'
  exit 0
elif [[ -z $(aws --output text iam list-users | grep "$USER_NAME") ]]; then
  echo "User '"$USER_NAME"' not found!"
  exit 1
else
  read -p "You are about to remove '"$USER_NAME"' from the AWS account. Are you sure you want to do this? " answer
    if [[ "$answer" == "n" ]] || [[ "$answer" == "no" ]]; then
      echo "Quitting.."
      exit 0
    fi
fi

# remove Access keys
ACC_KEY=$(aws iam list-access-keys --user-name "$USER_NAME" --output text --query 'AccessKeyMetadata[*].AccessKeyId' 2>/dev/null)
if [ ! -z "$ACC_KEY" ]; then
  echo "$ACC_KEY" | while read -r KEY_LIST; do
    aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$KEY_LIST"
  done
else
  echo "$USER_NAME" 'has no Access Keys'
fi

# remove certificates
CERT_ID=$(aws iam list-signing-certificates --user-name "$USER_NAME" --output text --query 'Certificates[*].CertificateId')
if [ ! -z "$CERT_ID" ]; then
  echo "$CERT_ID" | while read -r CERT_LIST; do
    aws iam delete-signing-certificate --user-name "$USER_NAME" --certificate-id "$CERT_LIST"
  done
else
  echo "$USER_NAME" 'has no Certificates'
fi

# remove login profile/password
aws iam delete-login-profile --user-name "$USER_NAME"

# remove MFA devices
MFA_ID=$(aws iam list-mfa-devices --user-name "$USER_NAME" --query 'MFADevices[*].SerialNumber')
if [ ! -z "$MFA_ID" ]; then
  echo "$MFA_ID" | while read -r MFA_LIST; do
    aws iam deactivate-mfa-device --user-name "$USER_NAME" --serial-number "$MFA_LIST"
  done
else
  echo "$USER_NAME" 'has no MFA devices (not a good thing)'
fi

# detach user policies
USER_POLICY=$(aws iam list-attached-user-policies --user-name "$USER_NAME" --query 'AttachedPolicies[*].PolicyArn')
if [ ! -z "$USER_POLICY" ]; then
  echo "$USER_POLICY" | while read -r POLICIES; do
    aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICIES"
  done
fi

# remove user from groups
GRP_NAME=$(aws iam list-groups-for-user --user-name "$USER_NAME" --query 'Groups[*].GroupName' | tr -s '\t' '\n')
if [ ! -z "$GRP_NAME" ]; then
  echo "$GRP_NAME" | while read -r GRP; do
    aws iam remove-user-from-group --user-name "$USER_NAME" --group-name "$GRP"
  done
fi

# get user CIDR (to remove from Security Groups)
CIDR=$(aws ec2 describe-security-groups | grep "$USER_NAME" | awk '{print $2}' | head -1)

# remove user from security groups
SG_GRP=$(aws ec2 describe-security-groups --filter Name=ip-permission.cidr,Values="$CIDR" --query 'SecurityGroups[*].GroupId')
if [ ! -z "$SG_GRP" ]; then
  echo "$SG_GRP" | while read -r SGGRP; do
    aws ec2 revoke-security-group-ingress --group-id "$SGGRP" --cidr $CIDR --protocol all
  done
fi

# delete the user
aws iam delete-user --user-name "$USER_NAME"

# unset the alias
unalias aws

echo "Done"