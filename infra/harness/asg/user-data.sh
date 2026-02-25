#!/bin/bash
set -e

# App is pre-installed in AMI at /opt/app/app.jar
# Systemd service is pre-configured and enabled

# Start the application
systemctl start spring-boot-app

# Wait for app to be healthy
echo "Waiting for application to start..."
for i in {1..30}; do
  if curl -s http://localhost:8080/actuator/health | grep -q '"status":"UP"'; then
    echo "Application is healthy"
    exit 0
  fi
  sleep 2
done

echo "Application failed to start within 60 seconds"
exit 1
