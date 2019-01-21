resource "aws_ecs_task_definition" "batch2" {
  family                   = "${local.name}-2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"

  container_definitions = <<DEFINITION
[
  {
    "name": "${local.name}-2",
    "image": "${aws_ecr_repository.batch2.repository_url}:latest",
    "entryPoint": ["sh", "-c"],
    "command": ["python ./src/batch_job.py"],
    "essential":true,
    "networkMode": "awsvpc",
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.batch2.name}",
        "awslogs-region": "${var.aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
DEFINITION

  # ecsTaskExecutionRole required to pull image from ECR or log Cloudwatch
  execution_role_arn = "${aws_iam_role.ecs_task_execution_role.arn}"
}

resource "aws_cloudwatch_log_group" "batch2" {
  name              = "/ecs/${local.name}-2"
  retention_in_days = 7
}

resource "aws_ecr_repository" "batch2" {
  name = "${local.name}-2"
}

output "batch_repository_name2" {
  value = "${aws_ecr_repository.batch2.name}"
}

output "batch_repository_url2" {
  value = "${aws_ecr_repository.batch2.repository_url}"
}
