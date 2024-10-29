data "aws_route53_zone" "hosted_zone" {
  name         = var.subdomain_name
  private_zone = false
}

resource "aws_route53_record" "app_a_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = var.subdomain_name
  type    = "A"
  ttl     = 300
  records = [aws_instance.web_app_instance.public_ip]

  #   depends_on = [aws_instance.web_app_instance]
}
