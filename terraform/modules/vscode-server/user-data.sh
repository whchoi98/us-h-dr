#!/bin/bash
set -e

# System updates
dnf update -y
dnf install -y docker git jq python3 python3-pip

# Start Docker
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user

# Node.js 20 via fnm
curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/bin
eval "$(fnm env)"
fnm install 20
fnm default 20

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

# kubectl
curl -LO "https://dl.k8s.io/release/v1.33.0/bin/linux/arm64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# eksctl
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_arm64.tar.gz" | tar xz -C /usr/local/bin

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# code-server v4.110.0
curl -fsSL https://code-server.dev/install.sh | sh -s -- --version 4.110.0

# Configure code-server
mkdir -p /home/ec2-user/.config/code-server
cat > /home/ec2-user/.config/code-server/config.yaml << 'CONF'
bind-addr: 0.0.0.0:8888
auth: password
password: ${vscode_password}
cert: false
CONF
chown -R ec2-user:ec2-user /home/ec2-user/.config

# Systemd service
cat > /etc/systemd/system/code-server.service << 'SVC'
[Unit]
Description=code-server
After=network.target
[Service]
Type=simple
User=ec2-user
ExecStart=/usr/bin/code-server
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

# pip packages for test data generation
pip3 install faker psycopg2-binary pymongo tqdm boto3
