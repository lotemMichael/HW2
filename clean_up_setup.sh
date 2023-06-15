#!/bin/bash

# Delete security group
echo "Deleting security group..."
aws ec2 describe-security-groups --query 'SecurityGroups[*].[GroupName, GroupId]' --output text

# Delete instance profile
echo "Deleting instance profile..."
aws iam remove-role-from-instance-profile --instance-profile-name MyInstanceProfile --role-name Lotem-Raz_IAM_Role
aws iam delete-instance-profile --instance-profile-name MyInstanceProfile

# Detach policies from IAM role
echo "Detaching policies from IAM role..."
for policy in $(aws iam list-attached-role-policies --role-name Lotem-Raz_IAM_Role --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name Lotem-Raz_IAM_Role --policy-arn "$policy"
done

# Delete IAM role
echo "Deleting IAM role..."
aws iam delete-role --role-name Lotem-Raz_IAM_Role

echo "Deleting instance profile..."
aws iam delete-instance-profile --instance-profile-name MyInstanceProfile

# Terminate all EC2 instances
echo "Terminating all EC2 instances..."
aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output text)

# Wait for instances to terminate
echo "Waiting for instances to terminate..."
aws ec2 wait instance-terminated

# Delete key pair
echo "Deleting key pair..."
aws ec2 delete-key-pair --key-name Lotem-Raz_Key

echo "Removing Lotem-Raz_Key.pem file..."
rm Lotem-Raz_Key.pem

echo "Cleanup completed successfully."
