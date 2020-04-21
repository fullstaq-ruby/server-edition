#!/bin/bash

function create_package()
{
    header "Creating package"
    run_curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -X POST \
        -H 'Content-Type: application/json' \
        -d '{
          "name": "fullstaq-ruby",
          "licenses": ["BSD 2-Clause", "MIT"],
          "vcs_url": "https://github.com/fullstaq-labs/fullstaq-ruby-server-edition.git",
          "issue_tracker_url": "https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/issues",
          "maturity": "Development",
          "public_download_numbers": true,
          "public_stats": true
        }' \
        "https://bintray.com/api/v1/packages/$BINTRAY_ORG/$REPO_NAME"
    verify_http_code_ok
    echo
}

function create_version()
{
    header "Creating version"
    run_curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -X POST \
        -H 'Content-Type: application/json' \
        -d '{ "name": "all" }' \
        "https://bintray.com/api/v1/packages/$BINTRAY_ORG/$REPO_NAME/fullstaq-ruby/versions"
    verify_http_code_ok
    echo
}
