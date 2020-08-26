# Troubleshooting corrupt CI/CD artifacts

Artifacts produced by the CI could become corrupted due to an external problem, for temporary network data corruption. When that happens, re-running the CI run will not mitigate the problem. That's because our CI implements [resumption support](ci-cd-resumption.md), which means that the CI run won't regenerate artifacts. Instead, any corrupted artifacts that are already stored in Google Cloud Storage, will remain there.

When this problem occurs, you should file a support ticket with the [infrastructure team](https://github.com/fullstaq-labs/fullstaq-ruby-infra), telling them to clear the artifacts in Google Cloud Storage.

 1. Go to the [infrastructure issue tracker](https://github.com/fullstaq-labs/fullstaq-ruby-infra/new/choose).
 2. Create a "Clear CI artifacts" ticket and fill in the template.
