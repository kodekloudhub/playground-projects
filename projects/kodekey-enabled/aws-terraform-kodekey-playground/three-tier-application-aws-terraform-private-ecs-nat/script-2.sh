terraform init
terraform apply \
  -target=aws_ecr_repository.app \
  -target=aws_ecr_repository.search \
  -auto-approve

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
  echo "AWS region is not configured. Set AWS_REGION and run: aws configure set region \"$AWS_REGION\""
  exit 1
fi
ENVIRONMENT="prod"
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

APP_REPOSITORY="$ECR_REGISTRY/${ENVIRONMENT}-app-repo"
SEARCH_REPOSITORY="$ECR_REGISTRY/${ENVIRONMENT}-search-repo"

docker tag egglou/nova:searxng "$SEARCH_REPOSITORY:latest"
docker push "$SEARCH_REPOSITORY:latest"

docker tag egglou/nova:latest "$APP_REPOSITORY:latest"
docker push "$APP_REPOSITORY:latest"

aws ecr describe-images --repository-name prod-app-repo --region "$AWS_REGION"
aws ecr describe-images --repository-name prod-search-repo --region "$AWS_REGION"
