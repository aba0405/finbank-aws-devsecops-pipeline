########################################
# Phase 2a: Network (VPC + public subnets)
#
# Design decisions (documented for the portfolio writeup):
#  - PUBLIC subnets only, NO NAT gateway. Fargate tasks get public IPs and
#    reach ECR/CloudWatch via the internet gateway. This saves ~$32/mo in NAT
#    cost. TRADEOFF: in production you'd run tasks in PRIVATE subnets behind a
#    NAT (or VPC endpoints) so they have no direct internet path. We compensate
#    with tight security groups (added in 2c) so tasks are only reachable
#    through the ALB, never directly.
#  - Two AZs. The ALB requires at least two subnets in different AZs, so two is
#    the minimum for a working load balancer. Keeps the footprint small.
#  - Uses the community-standard terraform-aws-modules/vpc module (v6), pinned.
########################################

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "finbank-vpc"
  cidr = "10.0.0.0/16"

  # First two available AZs in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Public subnets only. No private_subnets block => no private subnets,
  # and with enable_nat_gateway=false there is no NAT to pay for.
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = false
  single_nat_gateway = false

  # DNS support is required so tasks can resolve ECR / CloudWatch endpoints.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Auto-assign public IPs to anything launched in the public subnets.
  # Fargate tasks need this to pull the image without a NAT.
  map_public_ip_on_launch = true

  tags = {
    Project = "finbank-digital"
  }
}

########################################
# Outputs the later sub-steps (ALB, ECS) will consume.
########################################
output "vpc_id" {
  description = "VPC ID for security groups, ALB, and ECS."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the ALB and Fargate tasks."
  value       = module.vpc.public_subnets
}
