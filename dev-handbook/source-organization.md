# Source organization

Build and release scripts:

 * `build-*` — most of these scripts are for executing a specific [build step](build-steps.md).
 * `test-*` — [tests a Ruby package](testing-packages-locally.md).
 * `upload-*` — publishes built packages to repositories.

[Build workflow management](build-workflow-management.md) scripts and files:

 * `config.yml` — specifies which distributions, variants, Ruby versions and [fullstaq-rbenv](https://github.com/fullstaq-labs/fullstaq-rbenv) version we want to build for.

[Build environments](build-environments.md) related:

 * `build-environment-image` — builds a specific build environment's Docker image.
 * `push-environment-images` — Publishes all build environment Docker images to the Docker registry.
 * `environments/` — Docker images for all build environments.

Other:

 * `fullstaq-ruby.asc` — the GPG public key that can be used to verify the APT and YUM repositories. This file is referred to by the YUM .repo file mentioned in the installation documentation.

 * `container-entrypoints/` — because of [the "minimal dependencies" principle](minimal-dependencies-principle.md), most of the scripts in the root directory delegate work to a Docker container, in which it runs a corresponding script in this subdirectory.

   Scripts in this subdirectory may require further libraries, or call further scripts. Those required libraries and scripts are not located within this subdirectory.

 * `internal-scripts/` — scripts that are only invoked by other scripts in this repo, and are not supposed to be invoked by users.

 * `lib/` — libraries used by other scripts in this repo.

 * `resources/` — miscellaneous resources used by other scripts/code in this repo.

 * `resources/test-env` — files used by the [package testing script](testing-packages-locally.md).

## Root directory may only contain "public" scripts

The root directory may only contain scripts that are actually supposed to be invoked by users. If a script is considered internal, i.e. only invoked by other scripts, then put them in `internal-scripts/`.
