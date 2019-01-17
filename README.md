# AWS Step Functions Fargate Batch Example

* Terraform Fargate batch job example using Step Functions
* based on the official sample `Manage a Container Task (ECS, SNS)`
* plus adding ECR image and CloudWatch Logs to check the batch output


## How to run

### Run the official project

* When you follow the official doc, it will run CloudFormation
* and you can find the details in CloudFormation > Stacks
* `official-sample` will create same as the sample project by Terraform
* you can run this `official-sample` independently from `terraform/main.tf`
* This will run `echo` command in the image from docker hub

```bash
cd official-sample
terraform apply
```


### Run this example

* first create Fargate cluster/task and Step Functions state machine

```bash
cd terraform

# after check and update variables.tf or locals
terraform apply

export BATCH_REPO_NAME=$(terraform output batch_repository_name)
export BATCH_REPO_URL=$(terraform output batch_repository_url)
```

* next build and push simple docker image for Fargate batch job

```bash
cd batch-job

# build docker image
docker build -t my-python-batch .

# check if it is working
docker run --rm my-python-batch

# push to ECR
$(aws ecr get-login --region ap-northeast-1 --no-include-email)
docker tag my-python-batch ${BATCH_REPO_URL}:latest
docker push ${BATCH_REPO_URL}:latest

# check the result
aws ecr list-images --repository-name ${BATCH_REPO_NAME}
```

* go to Step Functions > State Machines and click Start Execution
* go to CloudWatch > Logs > Filter: `/ecs/${BATCH_REPO_NAME}`
* click the Log Streams to see the batch job output


## Notes

* how to check Fargate cluster arn
```
aws ecs describe-clusters --clusters tf-example-app
```


## Reference

* official sample project `Manage a Container Task (ECS, SNS)`
  - https://docs.aws.amazon.com/step-functions/latest/dg/sample-project-container-task-notification.html
* some note when you create new state machine
  - https://stackoverflow.com/questions/44402401
* https://hackernoon.com/incorporate-aws-fargate-into-step-functions-8003d688d027
