# 1. Store Outputs for Querying
export VPC_ID=$(terraform output -raw vpc_id)
export ALB_SG_ID=$(terraform output -raw alb_security_group_id)
export APP_SG_ID=$(terraform output -raw app_security_group_id)
export DB_SG_ID=$(terraform output -raw db_security_group_id)

# 2. Verify the Load Balancer Provisioning
aws elbv2 describe-load-balancers \
  --names media-app-prod-alb \
  --query "LoadBalancers[*].{Name:LoadBalancerName, Scheme:Scheme, State:State.Code, AZs:join(', ', AvailabilityZones[*].ZoneName)}" \
  --output table

# 3. Verify VPC DNS Properties
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].{Name:Tags[?Key=='Name'].Value | [0], CidrBlock:CidrBlock, DnsSupport:EnableDnsSupport}"
aws ec2 describe-vpc-attribute --vpc-id $VPC_ID --attribute enableDnsHostnames --query "EnableDnsHostnames.Value"

# 4. Verify Subnets & AZ Distribution
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].{Name:Tags[?Key=='Name'].Value | [0], SubnetId:SubnetId, CidrBlock:CidrBlock, AZ:AvailabilityZone, MapPublicIp:MapPublicIpOnLaunch}" \
  --output table

# 5. Verify Routing Paths (IGW, Multi-NAT, and Isolated)
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[*].{Name:Tags[?Key=='Name'].Value | [0], Routes:Routes}" \
  --output json

# 6. Verify 3-Tier Chained Security Groups
# Check ALB SG
aws ec2 describe-security-groups --group-ids $ALB_SG_ID \
  --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpProtocol:IpProtocol, IpRanges:IpRanges[*].CidrIp}" \
  --output table

# Check App SG
aws ec2 describe-security-groups --group-ids $APP_SG_ID \
  --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpProtocol:IpProtocol, AllowedSourceGroup:UserIdGroupPairs[*].GroupId}" \
  --output table

# Check DB SG
aws ec2 describe-security-groups --group-ids $DB_SG_ID \
  --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpProtocol:IpProtocol, AllowedSourceGroup:UserIdGroupPairs[*].GroupId}" \
  --output table
