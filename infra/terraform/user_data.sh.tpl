#!/bin/bash
set -e

yum update -y
amazon-linux-extras install java-openjdk11 -y

mkdir -p /opt/app
cd /opt/app

aws s3 cp s3://${s3_bucket}/${jar_file} app.jar --region ${aws_region}

cat > /etc/systemd/system/spring-boot-app.service <<EOF
[Unit]
Description=Spring Boot Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
ExecStart=/usr/bin/java -jar /opt/app/app.jar --server.port=${app_port}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable spring-boot-app
systemctl start spring-boot-app
