#!/bin/bash 
#set -e 
export AWS_PAGER=""
AWS_ACCOUNT_ID=128724583202
region=us-east-1
CLUSTER_NAME=sports-api-cluster
SERVICE_NAME=sports-api-service
LB_NAME=sports-api-LB
TG_NAME=sports-api-TG
SECURITY_GROUP=sg-0016f12d747be3101
SUBNET_1=subnet-974651cb
SUBNET_2=subnet-ced1daa9

#ecr login
aws ecr create-repository --repository-name sports-api --region $region
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

#Build docker image and push it to the ECR repos
#docker build --platform linux/amd64 -t sports-api . 
#docker tag sports-api:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/sports-api:sports-api-latest 
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/sports-api:sports-api-latest 

#create the ALB 

aws elbv2 create-load-balancer --name $LB_NAME --type application --subnets $SUBNET_1 $SUBNET_2 --security-groups $SECURITY_GROUP
aws elbv2 create-target-group --name $TG_NAME --protocol HTTP --port 80 --vpc-id vpc-04e8cf7e \
    --target-type ip \
    --health-check-protocol HTTP \
    --health-check-port traffic-port \
    --health-check-path "/sports" \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 3 \
    --unhealthy-threshold-count 3 \
    --region $region

LB_ARN=$(aws elbv2 describe-load-balancers --names $LB_NAME --query "LoadBalancers[0].LoadBalancerArn" --output text --region $region)
echo "Load Balancer ARN: $LB_ARN"

TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --query "TargetGroups[0].TargetGroupArn" --output text --region $region)
echo "Target Group ARN: $TG_ARN"

aws elbv2 create-listener \
    --load-balancer-arn $LB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region $region

LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $LB_ARN --query "Listeners[0].ListenerArn" --output text --region $region)
echo "Listener ARN: $LISTENER_ARN"

#Configure ECS service 
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $region 
aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document file://ecs-tasks-trust-policy.json
aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws ecs register-task-definition --cli-input-json file://task.json 

TASK_DEF_ARN=$(aws ecs list-task-definitions --query "taskDefinitionArns[-1]" --output text --region $region)

sed -e "s|__CLUSTER_NAME__|$CLUSTER_NAME|g" \
    -e "s|__SERVICE_NAME__|$SERVICE_NAME|g" \
    -e "s|__TASK_DEF_ARN__|$TASK_DEF_ARN|g" \
    -e "s|__TG_ARN__|$TG_ARN|g" \
    -e "s|__SECURITY_GROUP__|$SECURITY_GROUP|g" \
    -e "s|__SUBNET_1__|$SUBNET_1|g" \
    -e "s|__SUBNET_2__|$SUBNET_2|g" ecs-simple-service-elb-template.json > ecs-simple-service-elb.json

aws ecs create-service --cluster $CLUSTER_NAME --cli-input-json file://ecs-simple-service-elb.json --region $region


#Create an API Gateway 
aws apigateway create-rest-api --name Sports-API --description "Sports API Gateway" --region $region
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='Sports-API'].id" --output text --region $region)

RESOURCE_NAME="sports"
PARENT_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[0].id" --output text --region $region)
aws apigateway create-resource --rest-api-id $API_ID --parent-id $PARENT_ID --path-part $RESOURCE_NAME

#RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[?pathPart=='sports'].id" --output text)                                                                                                       )
RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[?pathPart=='sports'].id" --output text)
echo "Resource ID for /sports: $RESOURCE_ID"

ALB_URL=$(aws elbv2 describe-load-balancers --names "sports-api-LB" --query "LoadBalancers[0].DNSName" --output text --region $region) 

aws apigateway put-method --rest-api-id $API_ID --resource-id $RESOURCE_ID --http-method GET --authorization-type "NONE" --region $region

aws apigateway put-integration --rest-api-id $API_ID --resource-id $RESOURCE_ID --http-method GET --type HTTP_PROXY --integration-http-method GET --uri "http://$ALB_URL/sports" --region $region

aws apigateway create-deployment --rest-api-id $API_ID --stage-name "new-stage"



