locals {
  name = "sfn-fargate-batch"
}

data "aws_caller_identity" "self" {}

##################################################
# Network
##################################################
resource "aws_vpc" "batch" {
  cidr_block = "10.0.0.0/16"

  tags {
    Name = "${local.name}"
  }
}

resource "aws_subnet" "batch1" {
  vpc_id     = "${aws_vpc.batch.id}"
  cidr_block = "10.0.0.0/24"

  tags {
    Name = "${local.name}"
  }
}

resource "aws_subnet" "batch2" {
  vpc_id     = "${aws_vpc.batch.id}"
  cidr_block = "10.0.1.0/24"

  tags {
    Name = "${local.name}"
  }
}

resource "aws_internet_gateway" "batch" {
  vpc_id = "${aws_vpc.batch.id}"
}

resource "aws_route_table" "batch" {
  vpc_id = "${aws_vpc.batch.id}"
}

resource aws_route "batch" {
  route_table_id         = "${aws_route_table.batch.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.batch.id}"
}

resource "aws_route_table_association" "batch1" {
  subnet_id      = "${aws_subnet.batch1.id}"
  route_table_id = "${aws_route_table.batch.id}"
}

resource "aws_route_table_association" "batch2" {
  subnet_id      = "${aws_subnet.batch2.id}"
  route_table_id = "${aws_route_table.batch.id}"
}

##################################################
# ECR
##################################################
resource "aws_ecr_repository" "batch" {
  name = "${local.name}"
}

output "batch_repository_name" {
  value = "${aws_ecr_repository.batch.name}"
}

output "batch_repository_url" {
  value = "${aws_ecr_repository.batch.repository_url}"
}

##################################################
# Fargate Cluster and Task
# note: no need aws_ecs_service for batch jobs
##################################################
resource "aws_ecs_cluster" "batch" {
  name = "${local.name}"
}

resource "aws_ecs_task_definition" "batch" {
  family                   = "${local.name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"

  container_definitions = <<DEFINITION
[
  {
    "name": "${local.name}",
    "image": "${aws_ecr_repository.batch.repository_url}:latest",
    "entryPoint": ["sh", "-c"],
    "command": ["python ./src/batch_job.py"],
    "essential":true,
    "networkMode": "awsvpc",
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.batch.name}",
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

resource "aws_cloudwatch_log_group" "batch" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

##############################
# IAM for ECS Task Execution
# ecsTaskExecutionRole is automatically created from console
# but it does not exist if only using cli
# threfore create new one just for sure
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.name}-ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.ecs_task_execution_role.json}"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = "${aws_iam_role.ecs_task_execution_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

##################################################
# Step Functions
##################################################
resource "aws_sfn_state_machine" "batch" {
  name     = "${local.name}"
  role_arn = "${aws_iam_role.step_functions_execution.arn}"

  definition = <<DEFINITION
{
  "Comment": "A Hello World example of the Amazon States Language using a Pass state",
  "StartAt": "Amazon ECS: Manage a task",
  "States": {
    "Amazon ECS: Manage a task": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "${aws_ecs_cluster.batch.arn}",
        "TaskDefinition": "${aws_ecs_task_definition.batch.arn}",
        "Overrides": {
          "ContainerOverrides": [
            {
              "Name": "${local.name}",
              "Environment": [
                {
                  "Name": "NAME",
                  "Value.$": "$.Comment"
                }
              ]
            }
          ]
        },
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": [
              "${aws_subnet.batch1.id}",
              "${aws_subnet.batch2.id}"
            ],
            "AssignPublicIp": "ENABLED"
          }
        }
      },
      "Next": "HelloWorld"
    },
    "HelloWorld": {
      "Type": "Pass",
      "Result": "Hello World!",
      "End": true
    }
  }
}
DEFINITION

  depends_on = [
    # note this direct dependency setting does not work
    # "aws_iam_role_policy.step_functions_execution",
    "null_resource.delay",
  ]
}

# Initial run will fail due to the timing issue
# * aws_sfn_state_machine.batch: Error creating Step Function State Machine:
# AccessDeniedException: Neither the global service principal states.amazonaws.com,
# nor the regional one is authorized to assume the provided role.
# https://github.com/hashicorp/terraform/issues/2869
# Therefore wait 10 seconds
# https://github.com/hashicorp/terraform/issues/17726#issuecomment-377357866

resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = "sleep 10"
  }

  triggers = {
    "before" = "${aws_iam_role_policy.step_functions_execution.id}"
  }
}

##############################
# IAM for Step Functions
resource "aws_iam_role" "step_functions_execution" {
  name               = "${local.name}-StepFunctionsExcutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.step_functions_execution.json}"
}

data "aws_iam_policy_document" "step_functions_execution" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "step_functions_execution" {
  name = "${local.name}"
  role = "${aws_iam_role.step_functions_execution.id}"

  # Policy type: Inline policy
  # StepFunctionsGetEventsForECSTaskRule is AWS Managed Rule
  # need iam:PassRole to use ECR and Cloudwatch Logs
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecs:RunTask"
            ],
            "Resource": [
                "${aws_ecs_task_definition.batch.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecs:StopTask",
                "ecs:DescribeTasks"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "events:PutTargets",
                "events:PutRule",
                "events:DescribeRule"
            ],
            "Resource": [
                "arn:aws:events:ap-northeast-1:${data.aws_caller_identity.self.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
            ]
        },
        {
            "Action": [
                "iam:PassRole"
            ],
            "Resource": [
                "arn:aws:iam::${data.aws_caller_identity.self.account_id}:role/${local.name}-ecsTaskExecutionRole"
            ],
            "Effect": "Allow"
        }
    ]
}
EOF
}
