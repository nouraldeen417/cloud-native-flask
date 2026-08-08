resource "aws_ecr_repository" "flask_app" {
  name = "${var.project_name}-flask-app"
  # MUTABLE: Allows overwriting an existing tag (e.g., repeatedly pushing to :latest).
  # This is useful for active development environments where you want to update 
  # an image without incrementing the version tag each time.

  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    # true: Automatically scans every pushed image for known vulnerabilities (CVEs) immediately.
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "flask_app_cleanup" {
  repository = aws_ecr_repository.flask_app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }]
  })
}
