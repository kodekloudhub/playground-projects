# Decoupled GitOps Inventory Pipeline

**Level:** advanced  ·  **Playground:** GitLab | AWS Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds)** — open it, then copy the files below.

## Files in this project
- [`.gitlab-ci.yml`](./.gitlab-ci.yml)
- [`app/app.py`](./app/app.py)
- [`app/requirements.txt`](./app/requirements.txt)
- [`app/templates/index.html`](./app/templates/index.html)
- [`infrastructure/template.yaml`](./infrastructure/template.yaml)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
The operations team is deploying a new Cloud Inventory Portal backed by AWS DynamoDB and an Auto Scaling Group of EC2 instances. Historically, infrastructure deployments were manual, error-prone, and failed to follow security best practices by exposing backend compute instances directly to the public internet. 

You are the Lead Cloud Automation Engineer. Your task is to log into GitLab and implement a fully automated GitOps workflow. You will author the Infrastructure as Code (CloudFormation) to isolate the backend compute inside secure private subnets routed through a NAT Gateway. Once the architecture is secured, you will author a GitLab CI/CD pipeline that automatically builds, deploys, and actively validates the application end-to-end to ensure the database layer is functioning correctly.

## What you'll build
Starting from a baseline GitLab repository and a fresh AWS environment, you will configure a self-hosted GitLab runner to execute your pipeline jobs. You will author a secure, highly available AWS CloudFormation template utilizing an Application Load Balancer, Private Subnets, and an Auto Scaling Group. Finally, you will construct a `.gitlab-ci.yml` pipeline containing Build, Deploy, and Validate stages. You will ensure the pipeline can dynamically test DynamoDB database writes and handle eventual consistency polling before marking the deployment as successful.

## Learning objectives
By the end you will be able to:
- Programmatically register and authenticate self-hosted GitLab CI/CD runners.
- Author highly available AWS CloudFormation templates isolating compute resources in private subnets.
- Write EC2 UserData scripts that securely bootstrap applications and sync artifacts from S3.
- Construct multi-stage GitLab CI/CD pipelines (`.gitlab-ci.yml`) for automated infrastructure provisioning.
- Implement automated validation scripts with polling loops for zero-downtime deployment verification.

## Prerequisites
- Playground: **GitLab** and **AWS Cloud Sandbox** - open both before starting.

---

## Steps

### Task 1 — Runner Initialization & Host Setup
In the GitLab Playground Terminal, install the packaging utilities and the AWS CLI.

```bash
sudo apt-get update -y
sudo apt-get install -y zip curl unzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
aws --version
```

Next, fetch the registration token programmatically directly from the GitLab backend database, then register the runner:

```bash
# 1. Fetch token directly from the GitLab backend (this command takes ~15 seconds to load)
REGISTRATION_TOKEN=$(sudo gitlab-rails runner -e production "puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token")

# 2. Register the runner
sudo gitlab-runner register \
  --non-interactive \
  --url "http://localhost/" \
  --registration-token "${REGISTRATION_TOKEN}" \
  --executor "shell" \
  --description "gitops-dynamo-runner"

sudo gitlab-runner start
sudo gitlab-runner verify
```

### Task 2 — Generate AWS Programmatic Credentials
1. Open the **AWS Cloud Sandbox** in a private browser tab and log into the AWS Console. 
2. Navigate to **IAM > IAM users**, select your sandbox user, and open the **Security credentials** tab.
3. Click **Create access key**. Select **Command Line Interface (CLI)** and copy the resulting **Access Key ID** and **Secret Access Key**. Keep these handy.

### Task 3 — Create the GitLab Project & Inject Secrets
1. Open the GitLab UI (Username: `root`, Password: `Adm!n321`).
2. Click **Create a project > Create blank project**.
3. Name the repository `cloud-inventory-portal`. 
   > **Critical:** Under Project URL, ensure you select **root** from the namespace dropdown. 
4. Uncheck "Initialize repository with a README", and click **Create project**.
5. Navigate to **Settings > CI/CD**. Expand **Variables**, click **Add variable**, and create the following three entries. Ensure you select the **Masked and hidden** button under **Visibility** for the secret keys:
   - `AWS_ACCESS_KEY_ID` — (Your AWS Access Key ID)
   - `AWS_SECRET_ACCESS_KEY` — (Your AWS Secret Access Key)
   - `AWS_DEFAULT_REGION` — `us-east-1`

### Task 4 — Initialize the Repository & Backend Code
Return to your terminal, initialize the local repository, and create the Python Flask application logic.

```bash
git config --global user.name "Cloud Engineer"
git config --global user.email "engineer@labs.local"
mkdir -p ~/cloud-inventory-portal/app/templates ~/cloud-inventory-portal/infrastructure
cd ~/cloud-inventory-portal
git init
git remote add origin http://localhost/root/cloud-inventory-portal.git
```

Create the backend API:
```bash
cat << 'EOF' > app/app.py
import os
import socket
import urllib.request
import boto3
from flask import Flask, render_template, request, redirect, url_for
import psutil

app = Flask(__name__)

TABLE_NAME = os.environ.get("DYNAMODB_TABLE", "InventoryItems")
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

def get_aws_metadata():
    meta = {"id": "Local-Node", "az": "Unknown-AZ", "ip": socket.gethostbyname(socket.gethostname())}
    try:
        token_req = urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT")
        token_req.add_header("X-aws-ec2-metadata-token-ttl-seconds", "21600")
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        headers = {"X-aws-ec2-metadata-token": token}

        meta["id"] = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/instance-id", headers=headers), timeout=1).read().decode()
        meta["az"] = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/placement/availability-zone", headers=headers), timeout=1).read().decode()
        meta["ip"] = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/local-ipv4", headers=headers), timeout=1).read().decode()
    except Exception:
        pass
    return meta

def seed_default_records():
    try:
        response = table.scan(Limit=1)
        if response.get("Count", 0) == 0:
            defaults = [
                {"item_id": "MOD-101", "name": "Core Compute Node", "category": "Compute", "stock": 25},
                {"item_id": "MOD-102", "name": "Edge Cache Appliance", "category": "Storage", "stock": 8},
                {"item_id": "MOD-103", "name": "Gigabit Fiber Switch", "category": "Networking", "stock": 14}
            ]
            with table.batch_writer() as batch:
                for item in defaults:
                    batch.put_item(Item=item)
    except Exception as err:
        print(f"DynamoDB initialization warning: {err}")

@app.route("/")
def index():
    seed_default_records()
    items = []
    try:
        resp = table.scan()
        items = resp.get("Items", [])
        items.sort(key=lambda x: x.get("item_id", ""))
    except Exception as err:
        print(f"Fetch failed: {err}")

    metadata = get_aws_metadata()
    stats = {
        "cpu": psutil.cpu_percent(),
        "mem": psutil.virtual_memory().percent
    }
    return render_template("index.html", meta=metadata, stats=stats, items=items)

@app.route("/items", methods=["POST"])
def create_item():
    item_id = request.form.get("item_id", "").strip()
    name = request.form.get("name", "").strip()
    category = request.form.get("category", "").strip()
    stock = int(request.form.get("stock", 0))

    if item_id and name:
        table.put_item(Item={
            "item_id": item_id,
            "name": name,
            "category": category,
            "stock": stock
        })
    return redirect(url_for("index"))

@app.route("/items/update", methods=["POST"])
def update_item():
    item_id = request.form.get("item_id")
    stock = int(request.form.get("stock", 0))
    if item_id:
        table.update_item(
            Key={"item_id": item_id},
            UpdateExpression="SET stock = :val",
            ExpressionAttributeValues={":val": stock}
        )
    return redirect(url_for("index"))

@app.route("/items/delete/<item_id>", methods=["POST"])
def delete_item(item_id):
    if item_id:
        table.delete_item(Key={"item_id": item_id})
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
```

Create the requirements file:
```bash
cat << 'EOF' > app/requirements.txt
Flask==3.0.0
Werkzeug==3.0.0
boto3==1.34.0
psutil==5.9.6
EOF
```

### Task 5 — Create the Frontend Dashboard
Generate the HTML template for the user interface.

```bash
cat << 'EOF' > app/templates/index.html
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloud Native Inventory Portal</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-black text-light">
    <div class="container py-4">
        <header class="d-flex justify-content-between align-items-center mb-4 pb-2 border-bottom border-secondary">
            <h2 class="text-primary mb-0">Inventory Operations Center</h2>
            <span class="badge bg-secondary">Backend: Amazon DynamoDB</span>
        </header>

        <div class="row g-4 mb-4">
            <div class="col-md-6">
                <div class="card bg-dark border-secondary h-100">
                    <div class="card-header border-secondary text-info fw-bold">Active Compute Node (ALB Routing)</div>
                    <div class="card-body">
                        <p class="mb-1"><strong>EC2 Instance ID:</strong> <span class="badge bg-warning text-dark">{{ meta.id }}</span></p>
                        <p class="mb-1"><strong>Availability Zone:</strong> <span class="text-info">{{ meta.az }}</span></p>
                        <p class="mb-2"><strong>Private IP Address:</strong> {{ meta.ip }}</p>
                        <small class="text-secondary">Refresh the browser to verify traffic distribution across healthy ASG instances.</small>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card bg-dark border-secondary h-100">
                    <div class="card-header border-secondary text-info fw-bold">Live Node Utilization</div>
                    <div class="card-body">
                        <div class="d-flex justify-content-between mb-1"><span>CPU Utilization:</span><span>{{ stats.cpu }}%</span></div>
                        <div class="progress mb-3" style="height: 10px;"><div class="progress-bar bg-info" style="width: {{ stats.cpu }}%"></div></div>
                        <div class="d-flex justify-content-between mb-1"><span>RAM Utilization:</span><span>{{ stats.mem }}%</span></div>
                        <div class="progress" style="height: 10px;"><div class="progress-bar bg-success" style="width: {{ stats.mem }}%"></div></div>
                    </div>
                </div>
            </div>
        </div>

        <div class="card bg-dark border-secondary mb-4">
            <div class="card-header border-secondary text-success fw-bold">Create New Inventory Item</div>
            <div class="card-body">
                <form action="/items" method="POST" class="row g-3">
                    <div class="col-md-3">
                        <input type="text" name="item_id" class="form-control bg-black text-light border-secondary" placeholder="SKU ID (e.g. SRV-909)" required>
                    </div>
                    <div class="col-md-4">
                        <input type="text" name="name" class="form-control bg-black text-light border-secondary" placeholder="Item Name" required>
                    </div>
                    <div class="col-md-3">
                        <select name="category" class="form-select bg-black text-light border-secondary">
                            <option value="Compute">Compute</option>
                            <option value="Storage">Storage</option>
                            <option value="Networking">Networking</option>
                            <option value="Security">Security</option>
                        </select>
                    </div>
                    <div class="col-md-1">
                        <input type="number" name="stock" class="form-control bg-black text-light border-secondary" placeholder="Qty" value="1" required>
                    </div>
                    <div class="col-md-1">
                        <button type="submit" class="btn btn-success w-100">Add</button>
                    </div>
                </form>
            </div>
        </div>

        <div class="card bg-dark border-secondary">
            <div class="card-header border-secondary text-light fw-bold">Persistent Inventory Records</div>
            <div class="card-body p-0">
                <div class="table-responsive">
                    <table class="table table-dark table-hover mb-0 align-middle">
                        <thead class="table-secondary">
                            <tr>
                                <th>Item SKU</th>
                                <th>Item Name</th>
                                <th>Category</th>
                                <th>Stock Status</th>
                                <th style="width: 250px;">Update Stock</th>
                                <th class="text-end">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {% for item in items %}
                            <tr>
                                <td class="fw-bold">{{ item.item_id }}</td>
                                <td>{{ item.name }}</td>
                                <td><span class="badge bg-secondary">{{ item.category }}</span></td>
                                <td>
                                    {% if item.stock < 10 %}
                                        <span class="badge bg-danger">{{ item.stock }} units (Low)</span>
                                    {% else %}
                                        <span class="badge bg-success">{{ item.stock }} units</span>
                                    {% endif %}
                                </td>
                                <td>
                                    <form action="/items/update" method="POST" class="d-flex gap-2">
                                        <input type="hidden" name="item_id" value="{{ item.item_id }}">
                                        <input type="number" name="stock" class="form-control form-control-sm bg-black text-light border-secondary" value="{{ item.stock }}" style="width: 90px;" required>
                                        <button type="submit" class="btn btn-sm btn-outline-warning">Update</button>
                                    </form>
                                </td>
                                <td class="text-end">
                                    <form action="/items/delete/{{ item.item_id }}" method="POST" onsubmit="return confirm('Delete this record?');">
                                        <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
                                    </form>
                                </td>
                            </tr>
                            {% endfor %}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
EOF
```

### Task 6 — Author the Infrastructure as Code Template
Define the secure AWS architecture, placing compute instances in private subnets with a NAT gateway.

```bash
cat << 'EOF' > infrastructure/template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  ArtifactBucket:
    Type: String

Resources:
  DynamoInventoryTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: !Sub "InventoryItems-${AWS::StackName}"
      BillingMode: PAY_PER_REQUEST
      AttributeDefinitions:
        - AttributeName: item_id
          AttributeType: S
      KeySchema:
        - AttributeName: item_id
          KeyType: HASH

  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true

  InternetGateway:
    Type: AWS::EC2::InternetGateway
  VPCGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: true
  Subnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1
      RouteTableId: !Ref PublicRouteTable

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.2.0/24
      AvailabilityZone: !Select [1, !GetAZs '']
      MapPublicIpOnLaunch: true
  Subnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet2
      RouteTableId: !Ref PublicRouteTable

  NatEIP:
    Type: AWS::EC2::EIP
    DependsOn: VPCGatewayAttachment
    Properties:
      Domain: vpc

  NatGateway:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatEIP.AllocationId
      SubnetId: !Ref PublicSubnet1

  PrivateSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.11.0/24
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: false

  PrivateSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.12.0/24
      AvailabilityZone: !Select [1, !GetAZs '']
      MapPublicIpOnLaunch: false

  PrivateRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC

  PrivateRoute:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGateway

  PrivateSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet1
      RouteTableId: !Ref PrivateRouteTable

  PrivateSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet2
      RouteTableId: !Ref PrivateRouteTable

  ALBSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Allow inbound HTTP from Internet
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0

  EC2SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Strictly accept port 5000 ONLY from ALB
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 5000
          ToPort: 5000
          SourceSecurityGroupId: !Ref ALBSecurityGroup

  AppRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "EC2-App-Role-${AWS::StackName}"
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
        - arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

  AppInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref AppRole

  AppLoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Subnets:
        - !Ref PublicSubnet1
        - !Ref PublicSubnet2
      SecurityGroups:
        - !Ref ALBSecurityGroup
      Scheme: internet-facing

  AppTargetGroup:
    Type: AWS::ElasticLoadBalancingV2::TargetGroup
    Properties:
      VpcId: !Ref VPC
      Port: 5000
      Protocol: HTTP
      TargetType: instance
      HealthCheckPath: /
      HealthCheckIntervalSeconds: 15

  AppListener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties:
      LoadBalancerArn: !Ref AppLoadBalancer
      Port: 80
      Protocol: HTTP
      DefaultActions:
        - Type: forward
          TargetGroupArn: !Ref AppTargetGroup

  AppLaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateData:
        ImageId: resolve:ssm:/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id
        InstanceType: t2.micro
        IamInstanceProfile:
          Arn: !GetAtt AppInstanceProfile.Arn
        SecurityGroupIds:
          - !GetAtt EC2SecurityGroup.GroupId
        UserData:
          Fn::Base64: !Sub |
            #!/bin/bash
            set -ex

            export DEBIAN_FRONTEND=noninteractive
            export NEEDRESTART_MODE=a
            export NEEDRESTART_SUSPEND=1

            sed -i 's/us-east-1\.ec2\.archive\.ubuntu\.com/archive.ubuntu.com/g' /etc/apt/sources.list
            echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

            apt-get update -y
            apt-get install -yq python3-pip python3-venv unzip awscli

            cd /home/ubuntu
            export DYNAMODB_TABLE="${DynamoInventoryTable}"
            export AWS_DEFAULT_REGION="${AWS::Region}"

            for attempt in $(seq 1 15); do
              aws s3 cp s3://${ArtifactBucket}/latest.zip . && break
              echo "S3 download attempt $attempt failed, retrying in 10s..."
              sleep 10
            done

            unzip -o latest.zip

            python3 -m venv venv
            source venv/bin/activate
            pip install -r requirements.txt
            nohup python app.py > /home/ubuntu/app.log 2>&1 &

  AppASG:
    Type: AWS::AutoScaling::AutoScalingGroup
    DependsOn: PrivateRoute
    Properties:
      VPCZoneIdentifier:
        - !Ref PrivateSubnet1
        - !Ref PrivateSubnet2
      LaunchTemplate:
        LaunchTemplateId: !Ref AppLaunchTemplate
        Version: !GetAtt AppLaunchTemplate.LatestVersionNumber
      MinSize: '2'
      MaxSize: '4'
      TargetGroupARNs:
        - !Ref AppTargetGroup

Outputs:
  ALBDnsName:
    Value: !GetAtt AppLoadBalancer.DNSName
  DynamoTableName:
    Value: !Ref DynamoInventoryTable
EOF
```

### Task 7 — Construct the CI/CD Pipeline
Create the `.gitlab-ci.yml` file to orchestrate the build, deployment, and end-to-end validation.

```bash
cat << 'EOF' > .gitlab-ci.yml
stages:
  - build
  - deploy
  - validate

package_and_upload:
  stage: build
  script:
    - ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    - BUCKET_NAME="gitops-artifacts-${ACCOUNT_ID}"
    - aws s3 mb s3://${BUCKET_NAME} || true
    - cd app && zip -r ../latest.zip app.py templates requirements.txt && cd ..
    - aws s3 cp latest.zip s3://${BUCKET_NAME}/latest.zip

deploy_infrastructure:
  stage: deploy
  script:
    - ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    - BUCKET_NAME="gitops-artifacts-${ACCOUNT_ID}"
    - |
      if aws cloudformation describe-stacks --stack-name GitOps-Dynamo-Stack > /dev/null 2>&1; then
        STACK_EXISTS=true
        echo "Existing stack detected. Will perform Instance Refresh after deploy."
      else
        STACK_EXISTS=false
        echo "First-time deployment detected. Will skip Instance Refresh."
      fi
    - echo "Deploying CloudFormation Stack..."
    - aws cloudformation deploy --template-file infrastructure/template.yaml --stack-name GitOps-Dynamo-Stack --parameter-overrides ArtifactBucket=${BUCKET_NAME} --capabilities CAPABILITY_NAMED_IAM
    - |
      if [ "$STACK_EXISTS" = true ]; then
        echo "Triggering Auto Scaling Group Instance Refresh for Zero-Downtime Deployment..."
        ASG_NAME=$(aws cloudformation describe-stack-resources --stack-name GitOps-Dynamo-Stack --query "StackResources[?ResourceType=='AWS::AutoScaling::AutoScalingGroup'].PhysicalResourceId" --output text)
        aws autoscaling start-instance-refresh --auto-scaling-group-name $ASG_NAME --preferences '{"InstanceWarmup": 180, "MinHealthyPercentage": 50}'
        echo "Waiting for Instance Refresh to complete..."
        while true; do
          STATUS=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name $ASG_NAME --query "InstanceRefreshes[0].Status" --output text)
          if [ "$STATUS" == "Successful" ]; then echo "Refresh successful!"; break; fi
          if [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ]; then echo "Refresh failed!"; exit 1; fi
          echo "Refresh in progress... Status: $STATUS"
          sleep 30
        done
      fi

automated_validation:
  stage: validate
  script:
    - echo "Retrieving ALB Public Endpoint..."
    - ALB_DNS=$(aws cloudformation describe-stacks --stack-name GitOps-Dynamo-Stack --query "Stacks[0].Outputs[?OutputKey=='ALBDnsName'].OutputValue" --output text)
    - echo "Target endpoint is http://${ALB_DNS}"
    - echo "Polling ALB until instances are healthy..."
    - |
      HEALTHY=false
      for i in $(seq 1 40); do
        if curl -sf "http://${ALB_DNS}" | grep -q "Inventory Operations Center"; then
          echo "UI is up and healthy!"
          HEALTHY=true
          break
        fi
        echo "Waiting 20 seconds... (Attempt $i/40)"
        sleep 20
      done
      if [ "$HEALTHY" != "true" ]; then
        echo "ERROR: ALB never returned a healthy response after 40 attempts"
        exit 1
      fi
    - echo "Test 2 - Create a record via HTTP POST..."
    - curl -sf -X POST -d "item_id=CI-TEST-99&name=Pipeline-Verified-Node&category=Security&stock=42" "http://${ALB_DNS}/items"
    - echo "Test 3 - Verify item appears in DynamoDB scan..."
    - |
      FOUND=false
      for attempt in $(seq 1 15); do
        sleep 5
        if curl -sf "http://${ALB_DNS}" | grep -q "CI-TEST-99"; then
          echo "CI-TEST-99 found in UI!"
          FOUND=true
          break
        fi
        echo "Item not yet visible, retrying... (Attempt $attempt/15)"
      done
      if [ "$FOUND" != "true" ]; then
        echo "ERROR: CI-TEST-99 was not found in the UI after 15 attempts"
        exit 1
      fi
    - echo "End-to-End Validation Successful!"
EOF
```

### Task 8 — CI/CD Execution & User Interface Verification
Trigger the deployment stage, commit, and push your repository to GitLab to initiate the automated workflow.

```bash
git add .
git commit -m "feat: deployment of clean 3-tier gitops pipeline"
git push origin master
```
> **Note:** Enter Username `root` and Password `Adm!n321` when prompted.

**Monitor the Pipeline & UI:**
1. In the GitLab UI, navigate to **Build > Pipelines** and click on the running pipeline. Watch all three jobs successfully trigger and run.
2. Once complete, copy the ALB DNS Name printed at the end of the `automated_validation` job logs.
3. Open a new browser tab and navigate to `http://<ALB-DNS-NAME>`.
4. Refresh the page multiple times. Observe the Instance ID change to confirm the ALB is distributing traffic properly across your ASG nodes. 
5. Test Application CRUD logic by adding a new inventory item, updating a stock count, and deleting a row.

### Task 9 — Day 2 Operations (Continuous Deployment)
Now that the pipeline handles zero-downtime rolling updates via Instance Refreshes, simulate a Day 2 update. 

Change the title of the web application by dynamically searching and replacing the text:
```bash
grep -rl "Inventory Operations Center" . | xargs sed -i 's/Inventory Operations Center/Inventory Operations Center V2/g'
```

Commit the change and push it to the master branch:
```bash
git add .
git commit -m "feat: upgrade UI to V2"
git push origin master
```
> **What happens next?** 
> The Build stage zips the new code and uploads it to S3. The Deploy stage triggers an Instance Refresh. AWS slowly terminates the old EC2 instances one by one and launches new ones, executing the UserData script to download the new code. Finally, the Validate stage runs its end-to-end HTTP tests against the Load Balancer to guarantee the new code successfully connected to DynamoDB.

---

## Validation
Verify your GitLab runner and CI/CD operations.

1. **Verify your GitLab Runner is active and connected**
Run the following command in the terminal:
```bash
sudo gitlab-runner verify
```

2. **View the status of your deployed CloudFormation stack**
Navigate to the **AWS Management Console** in your browser and open the **CloudFormation** dashboard. Verify that your `GitOps-Dynamo-Stack` shows a status of `UPDATE_COMPLETE` or `CREATE_COMPLETE`.

Expected result:
- [ ] You successfully registered and authenticated the GitLab Runner on the host.
- [ ] You authored the CloudFormation template utilizing Private Subnets and a NAT Gateway.
- [ ] Your EC2 UserData successfully bootstrapped the instances and installed the required application dependencies.
- [ ] The GitLab CI/CD pipeline successfully triggered and deployed the AWS CloudFormation stack without errors.
- [ ] The Automated Validation stage successfully created a test record (`CI-TEST-99`) and passed the polling check against the Load Balancer endpoint.

## References & further learning
- GitLab CI/CD Pipeline Documentation: https://docs.gitlab.com/ee/ci/
- AWS CloudFormation EC2 AutoScaling Reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-autoscaling-autoscalinggroup.html
- AWS Instance Refresh Documentation: https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html
- KodeKloud course: GitLab CI/CD: Architecting, Deploying, and Optimizing Pipelines: https://kodekloud.com/courses/gitlab-ci-cd-architecting-deploying-and-optimizing-pipelines
- KodeKloud course: AWS CloudFormation: https://kodekloud.com/courses/aws-cloud-formation
