
# INSTANCE 1: K3s MASTER + LOCAL DATABASES (Docker)
# Runs: K3s server, PostgreSQL, Redis, OpenSearch via Docker
resource "aws_instance" "api_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type # t3.small for 2GB RAM
  
  key_name                    = aws_key_pair.k3s_key.key_name
  vpc_security_group_ids      = [aws_security_group.rapid_delivery_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 30 # Increased for Docker images and data
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data_api.sh", {
    AVAIL_IMAGE_URL       = aws_ecr_repository.availability_repo.repository_url
    ORDER_IMAGE_URL       = aws_ecr_repository.order_repo.repository_url
    FULFILLMENT_IMAGE_URL = aws_ecr_repository.fulfillment_repo.repository_url
    SQS_QUEUE_URL         = aws_sqs_queue.order_queue.url
    SNS_TOPIC_ARN         = aws_sns_topic.rapid_notifications.arn
    DB_PASSWORD           = var.db_password
    ACCOUNT_ID            = data.aws_caller_identity.current.account_id
    AWS_REGION            = var.aws_region
  })

  tags = { 
    Name = "RapidDelivery-Local-Master" 
    Role = "master"
    Setup = "local-docker-dbs"
  }
}

# INSTANCE 2: K3s WORKER (Optional - for extra compute capacity)
resource "aws_instance" "worker_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type # t3.micro
  
  key_name                    = aws_key_pair.k3s_key.key_name
  vpc_security_group_ids      = [aws_security_group.rapid_delivery_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data_worker.sh", {
    ACCOUNT_ID = data.aws_caller_identity.current.account_id
    AWS_REGION = var.aws_region
  })

  depends_on = [aws_instance.api_server]

  tags = { 
    Name = "RapidDelivery-Local-Worker"
    Role = "worker"
  }
}
