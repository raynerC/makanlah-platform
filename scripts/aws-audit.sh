#!/bin/bash
# aws-audit.sh — verify the account is at zero idle cost.
#
# Scans every enabled region for resources that bill while idle (EC2, EBS,
# EIPs, NAT gateways, load balancers, RDS, EKS, ECS, interface VPC endpoints,
# Secrets Manager, ECR) plus global services (S3, Route53, CloudFront).
# Run after every work session: the only expected output is the tfstate bucket.
#
# Usage:
#   ./scripts/aws-audit.sh          # live resource scan (free API calls)
#   ./scripts/aws-audit.sh --cost   # also print month-to-date spend by service
#                                   # (Cost Explorer queries cost $0.01 each)
set -u

if [ "${1:-}" = "--cost" ]; then
  start=$(date -u +%Y-%m-01)
  end=$(date -u -d "+1 day" +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)
  echo "=== Month-to-date cost by service ($start .. $end) ==="
  aws ce get-cost-and-usage \
    --time-period Start="$start",End="$end" \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --query "ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount!='0'].[Keys[0],Metrics.UnblendedCost.Amount]" \
    --output text
  echo
fi

regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
echo "=== Scanning regions: $regions"
found=0
for r in $regions; do
  ec2=$(aws ec2 describe-instances --region "$r" --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name,InstanceType]' --output text 2>/dev/null)
  [ -n "$ec2" ] && { echo "[$r] EC2: $ec2"; found=1; }
  vols=$(aws ec2 describe-volumes --region "$r" --query 'Volumes[].[VolumeId,State,Size]' --output text 2>/dev/null)
  [ -n "$vols" ] && { echo "[$r] EBS: $vols"; found=1; }
  eips=$(aws ec2 describe-addresses --region "$r" --query 'Addresses[].[PublicIp,AssociationId]' --output text 2>/dev/null)
  [ -n "$eips" ] && { echo "[$r] EIP: $eips"; found=1; }
  nat=$(aws ec2 describe-nat-gateways --region "$r" --filter Name=state,Values=available,pending --query 'NatGateways[].[NatGatewayId,State]' --output text 2>/dev/null)
  [ -n "$nat" ] && { echo "[$r] NAT-GW: $nat"; found=1; }
  lbs=$(aws elbv2 describe-load-balancers --region "$r" --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' --output text 2>/dev/null)
  [ -n "$lbs" ] && { echo "[$r] ELBv2: $lbs"; found=1; }
  clb=$(aws elb describe-load-balancers --region "$r" --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text 2>/dev/null)
  [ -n "$clb" ] && { echo "[$r] CLB: $clb"; found=1; }
  rds=$(aws rds describe-db-instances --region "$r" --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass]' --output text 2>/dev/null)
  [ -n "$rds" ] && { echo "[$r] RDS: $rds"; found=1; }
  rdsc=$(aws rds describe-db-clusters --region "$r" --query 'DBClusters[].[DBClusterIdentifier,Status]' --output text 2>/dev/null)
  [ -n "$rdsc" ] && { echo "[$r] RDS-Cluster: $rdsc"; found=1; }
  eks=$(aws eks list-clusters --region "$r" --query 'clusters' --output text 2>/dev/null)
  [ -n "$eks" ] && { echo "[$r] EKS: $eks"; found=1; }
  ecs=$(aws ecs list-clusters --region "$r" --query 'clusterArns' --output text 2>/dev/null)
  if [ -n "$ecs" ]; then
    echo "[$r] ECS clusters: $ecs"; found=1
    for c in $ecs; do
      tasks=$(aws ecs list-tasks --region "$r" --cluster "$c" --query 'taskArns' --output text 2>/dev/null)
      [ -n "$tasks" ] && echo "[$r]   RUNNING TASKS in $c: $tasks"
      svcs=$(aws ecs list-services --region "$r" --cluster "$c" --query 'serviceArns' --output text 2>/dev/null)
      [ -n "$svcs" ] && echo "[$r]   services in $c: $svcs"
    done
  fi
  vpce=$(aws ec2 describe-vpc-endpoints --region "$r" --query 'VpcEndpoints[?VpcEndpointType==`Interface`].[VpcEndpointId,ServiceName]' --output text 2>/dev/null)
  [ -n "$vpce" ] && { echo "[$r] VPC-Endpoint(Interface): $vpce"; found=1; }
  sec=$(aws secretsmanager list-secrets --region "$r" --query 'SecretList[].Name' --output text 2>/dev/null)
  [ -n "$sec" ] && { echo "[$r] Secrets: $sec"; found=1; }
  ecr=$(aws ecr describe-repositories --region "$r" --query 'repositories[].repositoryName' --output text 2>/dev/null)
  [ -n "$ecr" ] && { echo "[$r] ECR repos: $ecr"; found=1; }
done

echo "=== Global services ==="
echo "--- S3 buckets (tfstate bucket is expected):"
aws s3 ls
r53=$(aws route53 list-hosted-zones --query 'HostedZones[].[Name,Id]' --output text 2>/dev/null)
[ -n "$r53" ] && { echo "Route53 zones: $r53"; found=1; }
cf=$(aws cloudfront list-distributions --query 'DistributionList.Items[].[Id,Status,Enabled]' --output text 2>/dev/null)
[ -n "$cf" ] && [ "$cf" != "None" ] && { echo "CloudFront: $cf"; found=1; }

echo "=== SCAN COMPLETE ==="
if [ "$found" -eq 0 ]; then
  echo "RESULT: no idle-billable resources found."
else
  echo "RESULT: resources found above — verify each is intentional, then tear down."
fi
