#!/bin/bash

# Stops the script when encountering an error:
set -e

KEY_NAME="Lotem-Raz_Key"
KEY_PEM="$KEY_NAME.pem"
SEC_GRP="Lotem-raz_Security_Group"
IAM_ROLE_NAME="Lotem-Raz_IAM_Role"
INSTANCE_PROFILE_NAME="MyInstanceProfile"

echo "Creating key pair $KEY_PEM to connect to instances and saving locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# Secure the key pair
chmod 400 $KEY_PEM

echo "Setting up firewall $SEC_GRP"
aws ec2 create-security-group \
    --group-name $SEC_GRP \
    --description "Access my instances"

# Figure out my IP
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"

echo "Setting up rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

# TODO - check if this is good practice
echo "Setting up rule allowing HTTP (port 5000) access to all ips"
aws ec2 authorize-security-group-ingress \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --cidr 0.0.0.0/0

# Create the IAM role
aws iam create-role \
    --role-name $IAM_ROLE_NAME \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' 

# Attach the IAM policy to the role
aws iam attach-role-policy \
    --role-name $IAM_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

echo "IAM role $IAM_ROLE_NAME created with policy $IAM_POLICY_NAME"

# Create the IAM instance profile
aws iam create-instance-profile --instance-profile-name MyInstanceProfile

# Associate the IAM role with the instance profile
 aws iam add-role-to-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --role-name Lotem-Raz_IAM_Role

# Wait for the instance profile to become available
echo "waiting for the instance profile to become availble"
aws iam wait instance-profile-exists --instance-profile-name $INSTANCE_PROFILE_NAME
sleep 5

# Remove the "role/" prefix from the ARN to form the instance profile ARN
INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --query "InstanceProfile.Arn" --output text)

UBUNTU_22_04_AMI="ami-01dd271720c1ba44f"

echo "Creating the first Ubuntu 22.04 instance..."
RUN_INSTANCES_1=$(aws ec2 run-instances \
    --image-id $UBUNTU_22_04_AMI \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --security-groups $SEC_GRP \
    --iam-instance-profile "Arn=$INSTANCE_PROFILE_ARN" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EndpointNode_1}]')


INSTANCE_ID_1=$(echo $RUN_INSTANCES_1 | jq -r '.Instances[0].InstanceId')

echo "Waiting for the first instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_1

PUBLIC_IP_1=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID_1 |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID_1 @ $PUBLIC_IP_1"

echo "Creating the second Ubuntu 22.04 instance..."
RUN_INSTANCES_2=$(aws ec2 run-instances \
    --image-id $UBUNTU_22_04_AMI \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --security-groups $SEC_GRP \
    --iam-instance-profile "Arn=$INSTANCE_PROFILE_ARN" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EndpointNode_2}]')


INSTANCE_ID_2=$(echo $RUN_INSTANCES_2 | jq -r '.Instances[0].InstanceId')

echo "Waiting for the second instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_2

PUBLIC_IP_2=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID_2 |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID_2 @ $PUBLIC_IP_2"

# TODO: Deploy code to the first instance
echo "Deploying code to the first instance"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" endpoint.py worker_setup.sh worker.py ubuntu@$PUBLIC_IP_1:/home/ubuntu/

# TODO: Deploy code to the second instance
echo "Deploying code to the second instance"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" endpoint.py worker_setup.sh worker.py ubuntu@$PUBLIC_IP_2:/home/ubuntu/

# Connect to the first instance and execute commands
echo "Setting up the first instance"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1 <<EOF
    export NODE_NUM="1"
    export MY_IP=$PUBLIC_IP_1
    export SIBLING_IP=$PUBLIC_IP_2

    # Print the values of the exported variables
    echo "NODE_NUM: \$NODE_NUM"
    echo "MY_IP: \$MY_IP"
    echo "SIBLING_IP: \$SIBLING_IP"

    # Update package information
    sudo apt-get update

    # Install pip (Python package manager)
    sudo apt-get install -y python3-pip

    # Install jq
    #sudo apt-get install jq

    # Install AWS CLI
    pip3 install --upgrade awscli --user

    # Add AWS CLI to PATH
    echo 'export PATH=~/.local/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc

    # Install Flask
    pip3 install flask

    # Run the Flask app
    nohup python3 /home/ubuntu/endpoint.py > /dev/null 2>&1 &
    exit
EOF

# Connect to the second instance and execute commands
echo "Setting up the second instance"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2 <<EOF
    export NODE_NUM="2"
    export MY_IP=$PUBLIC_IP_2
    export SIBLING_IP=$PUBLIC_IP_1

    # Print the values of the exported variables
    echo "NODE_NUM: \$NODE_NUM"
    echo "MY_IP: \$MY_IP"
    echo "SIBLING_IP: \$SIBLING_IP"

    # Update package information
    sudo apt-get update

    # Install pip (Python package manager)
    sudo apt-get install -y python3-pip

    # Install jq
    #sudo apt-get install jq

    # Install AWS CLI
    pip3 install --upgrade awscli --user

    # Add AWS CLI to PATH
    echo 'export PATH=~/.local/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc

    # Install Flask
    pip3 install flask

    # Run the Flask app
    nohup python3 /home/ubuntu/endpoint.py > /dev/null 2>&1 &
    exit
EOF

echo "Adding sibling to endpoint num1:"
curl -X POST "http://${PUBLIC_IP_1}:5000/addSibling?endpoint=${PUBLIC_IP_2}:5000"
printf "\n"

echo "Adding sibling to endpoint num2:"
curl -X POST "http://${PUBLIC_IP_2}:5000/addSibling?endpoint=${PUBLIC_IP_1}:5000"
printf "\n"

echo "Finished setup script..." 

echo "dynamic_workload is up-"

echo "PUBLIC_IP_1: $PUBLIC_IP_1"

echo "PUBLIC_IP_2: $PUBLIC_IP_2"
