resource "github_repository_webhook" "shared" {
  repository = "homescale"
  events     = ["push", "pull_request"]
  active     = true

  configuration {
    url          = "https://REDACTED/webhook/v2/1916b8bd-f692-47f9-992d-9afa3396701a"
    content_type = "json"
    insecure_ssl = false
  }
}
