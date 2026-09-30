export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export RUN_ID=$(date -u +%m%d%H%M)
export FINOPS_BUCKET=cloud-cost-pulse-$ACCOUNT_ID-$RUN_ID

aws s3api create-bucket --bucket "$FINOPS_BUCKET" --region "$AWS_REGION"
aws s3api put-public-access-block --bucket "$FINOPS_BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$FINOPS_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-versioning --bucket "$FINOPS_BUCKET" --versioning-configuration Status=Enabled

for prefix in raw/events raw/manifests quarantine/events silver/events silver/rates gold/snapshots ai/audit; do
  aws s3api put-object --bucket "$FINOPS_BUCKET" --key "$prefix/.keep"
done

echo "FINOPS_BUCKET=$FINOPS_BUCKET"
