data "aws_route53_zone" "hosted_zone" {
  name         = var.subdomain_name
  private_zone = false
}

resource "aws_route53_record" "app_a_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = var.subdomain_name
  type    = "A"
  # records = [aws_instance.web_app_instance.public_ip] #LB_pub

  alias {
    name                   = aws_lb.app_load_balancer.dns_name # Reference to the load balancer's DNS
    zone_id                = aws_lb.app_load_balancer.zone_id  # Reference to the load balancer's hosted zone ID
    evaluate_target_health = true                              # Allows Route53 to evaluate the health of the load balancer
  }

  # depends_on ensures that the load balancer is created before the DNS record is created
  depends_on = [aws_lb.app_load_balancer]
}
