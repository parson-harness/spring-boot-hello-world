packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_name_prefix" {
  type    = string
  default = "spring-boot-hello-world"
}

variable "app_version" {
  type    = string
  default = "1.0-SNAPSHOT"
}

variable "jar_path" {
  type    = string
  default = "../../target/spring-boot-hello-world-1.0-SNAPSHOT.jar"
}

source "amazon-ebs" "spring-boot" {
  ami_name      = "${var.ami_name_prefix}-${var.app_version}"
  instance_type = var.instance_type
  region        = var.aws_region

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }

  ssh_username = "ec2-user"

  tags = {
    Name        = "${var.ami_name_prefix}-${var.app_version}"
    Application = "spring-boot-hello-world"
    Version     = var.app_version
    BuildTime   = "{{timestamp}}"
  }
}

build {
  sources = ["source.amazon-ebs.spring-boot"]

  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo amazon-linux-extras install java-openjdk11 -y",
      "sudo mkdir -p /opt/app",
      "sudo chown ec2-user:ec2-user /opt/app"
    ]
  }

  provisioner "file" {
    source      = var.jar_path
    destination = "/opt/app/app.jar"
  }

  provisioner "shell" {
    inline = [
      "sudo chown root:root /opt/app/app.jar",
      "sudo chmod 644 /opt/app/app.jar"
    ]
  }

  provisioner "shell" {
    inline = [
      <<-EOF
      sudo tee /etc/systemd/system/spring-boot-app.service > /dev/null <<'SYSTEMD'
      [Unit]
      Description=Spring Boot Application
      After=network.target

      [Service]
      Type=simple
      User=root
      WorkingDirectory=/opt/app
      ExecStart=/usr/bin/java -jar /opt/app/app.jar --server.port=8080
      Restart=always
      RestartSec=10

      [Install]
      WantedBy=multi-user.target
      SYSTEMD
      EOF
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo systemctl daemon-reload",
      "sudo systemctl enable spring-boot-app"
    ]
  }
}
