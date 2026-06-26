data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
# IAM role for EC2 instance — Fix CKV2_AWS_41
resource "aws_iam_role" "ec2_role" {
  name_prefix = "${var.environment}-ec2-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.environment}-ec2-role"
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${var.environment}-ec2-profile-"
  role        = aws_iam_role.ec2_role.name
}

resource "aws_security_group" "ec2_sg" {
  name_prefix = "${var.environment}-cicd-sg-"
  description = "Security group for ${var.environment} EC2 instances"

  ingress {
    description = "SSH access — restricted to known IPs only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # Private network only — not 0.0.0.0/0
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-cicd-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "app" {
  count         = var.instance_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # Fix CKV_AWS_126 — enable detailed monitoring
  monitoring = true

  # Fix CKV_AWS_135 — enable EBS optimization
  ebs_optimized = true

  # Fix CKV_AWS_79 — enforce IMDSv2 only (more secure)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Forces IMDSv2
    http_put_response_hop_limit = 1
  }

  # Fix CKV_AWS_8 — encrypt root EBS volume
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "${var.environment}-cicd-app-${count.index + 1}"
  }
}