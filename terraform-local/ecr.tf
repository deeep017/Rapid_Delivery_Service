# ECR Repositories - Container Registry (FREE: 500MB storage)

resource "aws_ecr_repository" "availability_repo" {
  name                 = "availability-service-local"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "order_repo" {
  name                 = "order-service-local"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "fulfillment_repo" {
  name                 = "fulfillment-worker-local"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}
