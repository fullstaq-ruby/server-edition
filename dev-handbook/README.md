# Development handbook

## Concepts

### Core concepts

 * [The "minimal dependencies" principle & the use of Docker](minimal-dependencies-principle.md) — on the fact that we don't require many dependencies to be installed on the local machine, and that instead we use dependencies through Docker.
 * [Package organization](package-organization.md) — which package types exist, what they are for, and how they relate to each other.
 * [Build steps](build-steps.md) — what steps are involved in order to build packages, and how they relate to each other.
 * [Build workflow management](build-workflow-management.md) — how we manage the fact that we have to build packages for multiple distributions, variants and Ruby versions.
 * [Build environments](build-environments.md) — how we utilize Docker images to build packages for different distributions and for running tasks.
 * [Source organization](source-organization.md) — how the Git repository is organized, and which files serve what purpose.

### Advanced concepts

 * [CI/CD system resumption support](ci-cd-resumption.md)
 * [CI/CD system and splitting into multiple workflows](ci-cd-split-multiple-workflows.md)

## Tutorials & tasks

### General

 * [Development environment set up](dev-environment-setup.md)
 * [Building packages locally](building-packages-locally.md)
 * [Fixing bugs](fixing-bugs.md)

### Testing

 * [Testing packages locally](testing-packages-locally.md)
 * [Adding, modifying & debugging tests](#modifying-and-debugging-tests.md)

### CI/CD

 * [Troubleshooting corrupt CI/CD artifacts](troubleshooting-corrupt-ci-cd-artifacts.md)
 * [Speeding up CI feedback](speeding-up-ci-feedback.md)

### Routine maintenance

 * [Adding support for a new distribution](add-new-distro.md)
 * [Adding support for a new Ruby version](add-new-ruby-version.md)

## Organizational (for team members)

 * [Way of working](way-of-working.md)
 * [Responsibilities & expectations](responsibilities-expectations.md)
 * [Members](members.md)
 * [Mentorship](mentorship.md)
 * [Onboarding](onboarding.md)
 * [Offboarding](offboarding.md)

## References & recommended reading

 * [How Debian packaging works](https://www.joyfulbikeshedding.com/blog/2020-08-03-how-debian-packaging-works.html)
 * [Inspecting & extracting RPM packages](https://blog.packagecloud.io/eng/2015/10/13/inspect-extract-contents-rpm-packages/)
 * [FPM manual](http://fpm.readthedocs.io/en/latest/)
 * [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)
