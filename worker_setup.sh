#!/bin/bash

# Stops the script when encountering an error:
set -e

# TODO - duplicate the script to worker A and worker B

aws configure set region us-east-1

KEY_NAME="Worker_Key"
KEY_PEM="$KEY_NAME.pem"
SEC_GRP="Worker_Security_Group"

UBUNTU_22_04_AMI="ami-01dd271720c1ba44f"

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

UBUNTU_22_04_AMI="ami-01dd271720c1ba44f"

echo "Creating the a worker..."
SPAWN_WORKER=$(aws ec2 run-instances \
    --image-id $UBUNTU_22_04_AMI \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --security-groups $SEC_GRP \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=$NODE_NUM_worker}]')

WORKER_ID=$(echo $SPAWN_WORKER | jq -r '.Instances[0].InstanceId')

echo "Waiting for the worker creation..."
aws ec2 wait instance-running --instance-ids $WORKER_ID

WORKER_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID_1 |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "Deploying code to the worker..."
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" worker.py ubuntu@$WORKER_IP:/home/ubuntu/

#Connect to the worker and execute commands
echo "Setting up the worker"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$WORKER_IP <<EOF

    # Update package information
    sudo apt-get update

    # Install pip (Python package manager)
    sudo apt-get install -y python3-pip

    # Install AWS CLI
    pip3 install --upgrade awscli --user

    # Install Flask
    pip3 install flask

    # Add AWS CLI to PATH
    echo 'export PATH=~/.local/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc

    #Run the Flask app
    nohup python3 /home/ubuntu/worker.py > /dev/null 2>&1 &
    exit
EOF