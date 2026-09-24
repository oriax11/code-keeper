# =====================================================
# COGNITO USER POOL (managed authentication)
# =====================================================

resource "aws_cognito_user_pool" "main" {
  name = "${var.environment}-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.environment}-user-pool"
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.environment}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Allow CLI/API auth so we can obtain tokens for testing.
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # OAuth settings (hosted UI / OIDC).
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = ["https://${var.lb_dns_name}/oauth2/idpresponse"]
  logout_urls   = ["https://${var.lb_dns_name}/"]
}
