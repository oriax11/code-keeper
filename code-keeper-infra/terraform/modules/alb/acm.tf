# =====================================================
# SELF-SIGNED CERTIFICATE IMPORTED INTO ACM
#
# A publicly trusted ACM certificate needs DNS validation of a domain we do
# not own, so we generate a self-signed certificate and import it. This still
# terminates real TLS at the ALB.
# =====================================================

resource "tls_private_key" "acm" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "acm" {
  private_key_pem = tls_private_key.acm.private_key_pem

  subject {
    common_name  = "${var.environment}.code-keeper.local"
    organization = "Code-Keeper"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  private_key      = tls_private_key.acm.private_key_pem
  certificate_body = tls_self_signed_cert.acm.cert_pem

  tags = {
    Name        = "${var.environment}-self-signed"
    Environment = var.environment
  }
}
