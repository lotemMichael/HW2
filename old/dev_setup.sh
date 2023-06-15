#!/bin/bash

# Stops the script when encountering an error:
set -e

KEY_NAME="Lotem-Raz_Key"
KEY_PEM="$KEY_NAME.pem"

echo "Creating key pair $KEY_PEM to connect to instances and saving locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# Secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="Lotem-raz_Security_Group2"

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

echo "Setting up rule allowing HTTP (port 5000) access to $MY_IP only"
aws ec2 authorize-security-group-ingress \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --cidr $MY_IP/32

UBUNTU_22_04_AMI="ami-01dd271720c1ba44f"

echo "Creating the first Ubuntu 22.04 instance..."
RUN_INSTANCES_1=$(aws ec2 run-instances \
    --image-id $UBUNTU_22_04_AMI \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --security-groups $SEC_GRP)

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
    --security-groups $SEC_GRP)

INSTANCE_ID_2=$(echo $RUN_INSTANCES_2 | jq -r '.Instances[0].InstanceId')

echo "Waiting for the second instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_2

PUBLIC_IP_2=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID_2 |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID_2 @ $PUBLIC_IP_2"

echo "Deploying code to the first instance"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" dynamic_workload.py ubuntu@$PUBLIC_IP_1:/home/ubuntu/

echo "Deploying code to the second instance"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" dynamic_workload.py ubuntu@$PUBLIC_IP_2:/home/ubuntu/

# Connect to the first instance and execute commands
echo "Setting up the first instance"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1 <<EOF
    # Install dependencies (assuming Ubuntu)
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip

    # Install Flask
    pip3 install flask

    exit
EOF

# Connect to the second instance and execute commands
echo "Setting up the second instance"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2 <<EOF
    # Install dependencies (assuming Ubuntu)
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip

    # Install Flask
    pip3 install flask

    exit
EOF

echo "Now you can Test that it all worked"


