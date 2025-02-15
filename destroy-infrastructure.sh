#!/bin/bash 
export AWS_PAGER=""
AWS_ACCOUNT_ID=128724583202
region=us-east-1
CLUSTER_NAME=sports-api-cluster
SERVICE_NAME=sports-api-service
LB_NAME=sports-api-LB
TG_NAME=sports-api-TG

LB_ARN=$(aws elbv2 describe-load-balancers --names $LB_NAME --query "LoadBalancers[0].LoadBalancerArn" --output text --region $region)
echo "Load Balancer ARN: $LB_ARN"

TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --query "TargetGroups[0].TargetGroupArn" --output text --region $region)
echo "Target Group ARN: $TG_ARN"

LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $LB_ARN --query "Listeners[0].ListenerArn" --output text --region $region)
echo "Listener ARN: $LISTENER_ARN"


aws ecs delete-task-definitions --task-definition sports-api-task
aws iam detach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam delete-role --role-name ecsTaskExecutionRole
aws ecs delete-service --cluster sports-api-cluster --service sports-api-service --force
aws ecs delete-cluster --cluster  sports-api-cluster
aws ecr delete-repository --repository-name sports-api --force

aws elbv2 delete-listener --listener-arn $LISTENER_ARN
aws elbv2 delete-target-group --target-group-arn $TG_ARN 
aws elbv2 delete-load-balancer --load-balancer-arn  $LB_ARN

API_ID=$(aws apigateway get-rest-apis --query "items[?name=='Sports-API'].id" --output text --region $region)
RESOURCE_IDS=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query "items[*].id" \
    --output text --region us-east-1)

for ID in $RESOURCE_IDS; do
    echo "Deleting resource: $ID"
    aws apigateway delete-resource --rest-api-id $API_ID --resource-id $ID --region us-east-1
done

aws apigateway delete-integration --rest-api-id $API_ID --resource-id $RESOURCE_ID --http-method GET --region us-east-1
aws apigateway delete-method --rest-api-id $API_ID --resource-id $RESOURCE_ID --http-method GET --region us-east-1

STAGES=$(aws apigateway get-stages --rest-api-id $API_ID --query "item[*].stageName" --output text --region us-east-1)

for STAGE in $STAGES; do
    echo "Deleting stage: $STAGE"
    aws apigateway delete-stage --rest-api-id $API_ID --stage-name $STAGE --region us-east-1
done

aws apigateway delete-rest-api --rest-api-id $API_ID --region us-east-1



