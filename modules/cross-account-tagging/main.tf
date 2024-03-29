data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_region" "current" {}

locals {
  environment = {
    ASSUME_ROLE = join(" ", [data.aws_iam_session_context.current.issuer_arn, "arn:aws:iam::${var.account_id}:role/${var.role_name}"])
    AWS_REGION  = data.aws_region.current.name
    RESOURCE_ID = var.resource_id
    SCRIPT_DIR  = "${path.module}/scripts"
    TAGS_CREATE = join(" ", [for key, value in var.tags : "Key=${key},Value=${value}"])
    TAGS_DELETE = join(" ", [for key, value in var.tags : "Key=${key}"])
  }
}

resource "terraform_data" "tags" {
  input = local.environment

  triggers_replace = [var.account_id, var.resource_id, var.tags]

  provisioner "local-exec" {
    when = create

    environment = merge(local.environment, {
      TAGS = local.environment.TAGS_CREATE
    })

    command = file("${path.module}/scripts/create-tags.sh")
  }

  provisioner "local-exec" {
    when = destroy

    environment = merge(self.input, {
      TAGS = self.input.TAGS_DELETE
    })

    command = file("${path.module}/scripts/delete-tags.sh")
  }

  lifecycle {
    ignore_changes = [input]
  }
}
