# Contribution guide

> You are reading the contribution guide for the **Server Edition**. Interested in contributing to other parts of Fullstaq Ruby? Check the [Fullstaq Ruby Umbrella contribution guide](https://github.com/fullstaq-ruby/umbrella/blob/main/CONTRIBUTING.md).

Thanks for considering to contribute! 😀 Your help is essential to [keeping Fullstaq Ruby great](https://www.joyfulbikeshedding.com/blog/2020-05-15-why-fullstaq-ruby.html). We welcome all contributions, no matter who you are, and no matter whether it's big or small (see also our [Code of Conduct](CODE_OF_CONDUCT.md)). With this guide, we aim to make contributing as clear and easy as possible.

## What counts as a contribution?

Anything that helps improving the project, whether directly (through a pull request) or indirectly (by engaging with us) counts as a contribution. Here's a non-exhaustive list:

 * Reporting an issue.
 * Triaging issues: determining whether an issue report is clear enough, whether the issue still persists, and whether it is reproducible.
 * Updating documentation.
 * Proposing an improvement.
 * Sending a pull request.
 * Reviewing someone else's pull request.

## Not sure how to get started?

Have a look at our [issue tracker](https://github.com/fullstaq-ruby/server-edition/issues). Issues with the following labels are good starting points:

 * "good first issue" if you're looking for something easy.
 * "help wanted" if you're in for a challenge, or if you want to help with a high-impact issue.

## Development handbook

To learn how the Fullstaq Ruby Server Edition codebase works and how to develop it, please read our [development handbook](dev-handbook/README.md).

## Testing your changes

### Automated CI on forks

When you push to your fork or open a pull request, a contributor CI workflow runs automatically. It:

 * Validates CI/CD workflow YAML is up-to-date.
 * Builds Ruby packages for two representative distributions (Ubuntu 24.04 and Enterprise Linux 9) with all three variants (normal, jemalloc, malloctrim).
 * Runs smoke tests that install the packages and verify Ruby works correctly.

No cloud credentials or special setup are needed — the workflow uses only Docker and GitHub Actions.

If a maintainer wants to run the full CI pipeline against your PR (which tests all distributions and publishes to test repositories), they will add the `ok-to-test` label. This label is automatically removed when you push new commits, so the maintainer must re-review and re-label after each update.

### Local builds and testing

For faster iteration, you can build and test packages on your own machine. You only need Docker and Ruby >= 3.2:

 * **Building packages:** see [Building packages locally](dev-handbook/building-packages-locally.md)
 * **Testing packages:** see [Testing packages locally](dev-handbook/testing-packages-locally.md)

## Stuck? Need help?

Please post something on our [discussion forum](https://github.com/fullstaq-ruby/server-edition/discussions).

## Joining the team

Anyone who wishes to contribute regularly to Fullstaq Ruby Server Edition, or who wishes to assume responsibility for the health and progress of this project, is welcome to join the team!

To learn more about what it means to be a team member, see [Responsibilities & expectations](dev-handbook/responsibilities-expectations.md).

### Trust

Because joining the team means gaining access to protected resources, trust is essential. We judge trustworthiness through the following manners:

 * Having an established relationship with either the Fullstaq Ruby project, or the wider Ruby community. The longer the better.
 * A contractual relationship (such as employment) with [Fullstaq B.V.](https://fullstaq.com/). Contractual relationships carry legal weight and provide greater likelihood of a stable trust relationship; at a minimum they establish strong legal accountability.

### Apply

If you wish to join, please [apply by submitting an issue](https://github.com/fullstaq-ruby/server-edition/issues/new?template=apply_join_team.md).
