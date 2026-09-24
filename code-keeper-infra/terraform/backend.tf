# ==============================================================================
# GitLab-Managed Terraform State (HTTP Backend)
# ==============================================================================
# When running inside GitLab CI/CD, the HTTP backend is dynamically initialized
# with the per-environment state URL and CI token:
#
#   terraform init \
#     -backend-config="address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CI_ENVIRONMENT_NAME}" \
#     -backend-config="lock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CI_ENVIRONMENT_NAME}/lock" \
#     -backend-config="unlock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CI_ENVIRONMENT_NAME}/lock" \
#     -backend-config="username=${GITLAB_USER_LOGIN}" \
#     -backend-config="password=${GITLAB_TOKEN}" \
#     -backend-config="lock_method=POST" \
#     -backend-config="unlock_method=DELETE" \
#     -backend-config="retry_wait_min=5"
# ==============================================================================

terraform {
  backend "http" {}
}
