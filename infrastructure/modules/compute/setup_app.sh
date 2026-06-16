#!/bin/bash

# SSM Agent
if ! systemctl is-active --quiet amazon-ssm-agent; then
  if command -v dnf &>/dev/null; then
    dnf install -y amazon-ssm-agent
  fi
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
fi

# Install packages
dnf install -y nginx python3-flask python3-boto3 python3-requests

# Create app directory
mkdir -p /opt/flaskapp

# Deploy Flask app
cat > /opt/flaskapp/app.py << 'PYEOF'
from flask import Flask, jsonify
import boto3
import json

app = Flask(__name__)

def get_db_credentials():
    client = boto3.client('secretsmanager', region_name='eu-north-1')
    secret = client.get_secret_value(SecretId='production/rds/mysql')
    return json.loads(secret['SecretString'])

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'}), 200

@app.route('/')
def index():
    creds = get_db_credentials()
    return jsonify({
        'message': 'Secure Flask App running',
        'db_host': creds.get('host'),
        'db_name': creds.get('dbname')
    }), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
PYEOF

# Create systemd service for Flask
cat > /etc/systemd/system/flaskapp.service << 'EOF'
[Unit]
Description=Flask Application
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/flaskapp
ExecStart=/usr/bin/python3 /opt/flaskapp/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Configure NGINX
cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self'" always;
    
    # Hide NGINX version
    server_tokens off;

    server {
        listen 80;
        server_name _;

        location /health {
            return 200 'healthy';
            add_header Content-Type text/plain;
        }

        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF

# Set ownership
chown -R ec2-user:ec2-user /opt/flaskapp

# Enable and start services
systemctl daemon-reload
systemctl enable nginx flaskapp
systemctl start nginx flaskapp