# Terraform version of official sample project
# CloudFormation Stack StepFunctionsSample-ContainerTaskManagement
#
# Run "terraform apply" to create followings
# * VPC, public subnet
# * Fargate cluster and batch task
# * Step Functions state machine

locals {
  project_name        = "StepFunctionsSample-ContainerTaskManagementa35322d8-223b-459c-b628-c39a1b825d3b"
  project_name_short  = "StepFunctionsSample-Conta"
  security_group_name = "${local.project_name}-ECSSecurityGroup-QPR6U2NZ32G7"
  ecs_cluster_name    = "${local.project_name}-ECSCluster-18FRCR9E7DGXQ"
  ecs_task_name       = "${local.project_name}-ECSTaskDefinition-A3Q1WB2SLKBK"
  state_machine_name  = "ECSTaskNotificationStateMachine-eZJJHP3fVjuh"
  iam_role_name       = "${local.project_name_short}-ECSRunTaskSyncExecutionR-5H2F3C2E3Z6W"
  iam_policy_name     = "FargateTaskNotificationAccessPolicy"
  sns_topic_name      = "${local.project_name}-SNSTopic-1S2TLVLE388TQ"
}

data "aws_caller_identity" "self" {}

##################################################
# Network
##################################################
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "example1" {
  vpc_id     = "${aws_vpc.example.id}"
  cidr_block = "10.0.0.0/24"

  tags {
    Name = "${local.ecs_cluster_name}/Public"
  }
}

resource "aws_subnet" "example2" {
  vpc_id     = "${aws_vpc.example.id}"
  cidr_block = "10.0.1.0/24"

  tags {
    Name = "${local.ecs_cluster_name}/Public"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = "${aws_vpc.example.id}"
}

resource "aws_route_table" "example" {
  vpc_id = "${aws_vpc.example.id}"
}

resource aws_route "example" {
  route_table_id         = "${aws_route_table.example.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.example.id}"
}

resource "aws_route_table_association" "example1" {
  subnet_id      = "${aws_subnet.example1.id}"
  route_table_id = "${aws_route_table.example.id}"
}

resource "aws_route_table_association" "example2" {
  subnet_id      = "${aws_subnet.example2.id}"
  route_table_id = "${aws_route_table.example.id}"
}

resource "aws_security_group" "example" {
  name                   = "${local.security_group_name}"
  description            = "ECS Allowed Ports"
  vpc_id                 = "${aws_vpc.example.id}"
  revoke_rules_on_delete = ""
}

resource "aws_security_group_rule" "example" {
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.example.id}"
}

##################################################
# Fargate
##################################################
resource "aws_ecs_cluster" "example" {
  name = "${local.ecs_cluster_name}"
}

resource "aws_ecs_task_definition" "example" {
  family                   = "${local.ecs_task_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = <<DEFINITION
[
  {
    "command": ["/bin/sh -c \"echo 'Hello from AWS Step Functions!'\""],
    "cpu":0,
    "dnsSearchDomains":[],
    "dnsServers":[],
    "dockerLabels":{},
    "dockerSecurityOptions":[],
    "entryPoint": ["sh", "-c"],
    "environment":[],
    "essential":true,
    "extraHosts":[],
    "image":"amazon/amazon-ecs-sample",
    "links":[],
    "mountPoints":[],
    "name": "fargate-app",
    "portMappings":[
      {
        "containerPort": 80,
        "hostPort":80,
        "protocol": "tcp"
      }
    ],
    "ulimits":[],
    "volumesFrom":[]
  }
]
DEFINITION
}

##################################################
# Step Functions
##################################################
resource "aws_sfn_state_machine" "example" {
  name     = "${local.state_machine_name}"
  role_arn = "${aws_iam_role.example.arn}"

  definition = <<DEFINITION
{
  "Comment": "An example of the Amazon States Language for notification on an AWS Fargate task completion",
  "StartAt": "Run Fargate Task",
  "TimeoutSeconds": 3600,
  "States": {
    "Run Fargate Task": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "${aws_ecs_cluster.example.arn}",
        "TaskDefinition": "${aws_ecs_task_definition.example.arn}",
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": [
              "${aws_subnet.example1.id}",
              "${aws_subnet.example2.id}"
            ],
            "AssignPublicIp": "ENABLED"
          }
        }
      },
      "Next": "Notify Success",
      "Catch": [
          {
            "ErrorEquals": [ "States.ALL" ],
            "Next": "Notify Failure"
          }
      ]
    },
    "Notify Success": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "Message": "AWS Fargate Task started by Step Functions succeeded",
        "TopicArn": "${aws_sns_topic.example.arn}"
      },
      "End": true
    },
    "Notify Failure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "Message": "AWS Fargate Task started by Step Functions failed",
        "TopicArn": "${aws_sns_topic.example.arn}"
      },
      "End": true
    }
  }
}DEFINITION
}

resource "aws_iam_role" "example" {
  name               = "${local.iam_role_name}"
  assume_role_policy = "${data.aws_iam_policy_document.example.json}"
}

data "aws_iam_policy_document" "example" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "example" {
  name = "${local.iam_policy_name}"
  role = "${aws_iam_role.example.id}"

  # Policy type: Inline policy
  # StepFunctionsGetEventsForECSTaskRule is AWS Managed Rule
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "sns:Publish"
            ],
            "Resource": [
                "${aws_sns_topic.example.arn}"
            ],
            "Effect": "Allow"
        },
        {
            "Action": [
                "ecs:RunTask"
            ],
            "Resource": [
                "${aws_ecs_task_definition.example.arn}"
            ],
            "Effect": "Allow"
        },
        {
            "Action": [
                "ecs:StopTask",
                "ecs:DescribeTasks"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "events:PutTargets",
                "events:PutRule",
                "events:DescribeRule"
            ],
            "Resource": [
                "arn:aws:events:ap-northeast-1:${data.aws_caller_identity.self.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
            ],
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_sns_topic" "example" {
  name = "${local.sns_topic_name}"
}
