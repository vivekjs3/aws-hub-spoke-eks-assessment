################################################################################
# alb.tf — Application Load Balancer (Hub VPC)
# Internet-facing ALB that serves as the entry point for all user traffic.
# Forwards requests through the TGW to the Istio Ingress Gateway in the Spoke.
################################################################################

################################################################################
# SECURITY GROUPS
################################################################################

# ─── ALB Security Group ───────────────────────────────────────────────────────
# Allows inbound 80/443 from the internet (0.0.0.0/0) as per spec.

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security Group for the internet-facing ALB in Hub VPC"
  vpc_id      = module.hub_vpc.vpc_id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound (to TGW / Spoke)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-alb-sg"
    Tier = "public"
  })
}

################################################################################
# APPLICATION LOAD BALANCER
################################################################################

resource "aws_lb" "hub" {
  name               = "${var.project_name}-hub-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.hub_vpc.public_subnets

  # Production hardening
  enable_deletion_protection       = false # set true in prod
  enable_cross_zone_load_balancing = true
  idle_timeout                     = 60

  # Access logs (uncomment and set bucket in production)
  # access_logs {
  #   bucket  = "your-alb-access-logs-bucket"
  #   prefix  = "hub-alb"
  #   enabled = true
  # }

  tags = merge(var.tags, {
    Name = "${var.project_name}-hub-alb"
    Tier = "public"
  })
}

################################################################################
# TARGET GROUP — Points to Istio Ingress Gateway port 80
# The Istio Ingress Gateway is exposed as an NLB/ClusterIP in the Spoke VPC.
# Traffic flows: ALB → TGW → Istio Ingress GW (IP target)
################################################################################

resource "aws_lb_target_group" "istio_ingress" {
  name        = "${var.project_name}-istio-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.hub_vpc.vpc_id
  target_type = "ip" # IP targets for cross-VPC routing via TGW

  health_check {
    enabled             = true
    path                = "/healthz/ready"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-istio-tg"
  })
}

################################################################################
# ALB LISTENERS
################################################################################

# HTTP Listener (port 80) — forwards to Istio target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.hub.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.istio_ingress.arn
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-alb-listener-http"
  })
}

# HTTPS Listener stub (port 443) — requires ACM certificate in production
# Uncomment and replace certificate_arn when ACM cert is provisioned
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.hub.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = "arn:aws:acm:ap-southeast-1:ACCOUNT_ID:certificate/CERT_ID"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.istio_ingress.arn
#   }
# }

################################################################################
# WAF Association (Optional — production recommendation)
################################################################################
# resource "aws_wafv2_web_acl_association" "alb" {
#   resource_arn = aws_lb.hub.arn
#   web_acl_arn  = aws_wafv2_web_acl.main.arn
# }
