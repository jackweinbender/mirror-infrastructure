locals {
  enabled_apis = [
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    # Google Workspace access for Hermes agent (Gmail, Calendar, Drive, Sheets, Docs, Contacts)
    "gmail.googleapis.com",
    "calendar-json.googleapis.com",
    "drive.googleapis.com",
    "sheets.googleapis.com",
    "docs.googleapis.com",
    "people.googleapis.com"
  ]
}

resource "google_project_service" "project" {
  for_each = toset(local.enabled_apis)
  service  = each.value
}
