# Development handbook

## Core concepts

 * [The "minimal dependencies" principle & the use of Docker](minimal-dependencies-principle.md) — on the fact that we don't require many dependencies to be installed on the local machine, and that instead we use dependencies through Docker.
 * [Package organization](package-organization.md) — which package types exist, what they are for, and how they relate to each other.
 * [Build steps](build-steps.md) — what steps are involved in order to build packages, and how they relate to each other.
 * [Build workflow management](build-workflow-management.md) — how we manage the fact that we have to build packages for multiple distributions, variants and Ruby versions.
 * [Build environments](build-environments.md) — how we utilize Docker images to build packages for different distributions and for running tasks.
 * [Source organization](source-organization.md) — how the Git repository is organized, and which files serve what purpose.

## Tutorials & tasks

 * [Development environment set up](dev-environment-setup.md)
 * [Building packages locally](building-packages-locally.md)
 * [Testing packages locally](testing-packages-locally.md) (coming soon)
 * [Adding support for a new distribution](add-new-distro.md) (coming soon)
 * [Adding support for a new Ruby version](add-new-ruby-version.md) (coming soon)

## References & recommended reading

 * [How Debian packaging works](https://www.joyfulbikeshedding.com/blog/2020-08-03-how-debian-packaging-works.html)
 * [FPM manual](http://fpm.readthedocs.io/en/latest/)
