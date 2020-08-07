# Build environments

## Distribution compilation environments

In order to build a package for a specific distribution, we must compile source code using that distribution. We use Docker for this purpose. For each distribution that we support, we maintain a Docker image in the directory `environments/<DISTRIBUTION>/`.

These images are used by the `build-ruby` and `build-jemalloc` scripts. These images contain a compiler toolchain, neccessary libraries, and whatever else is needed in order to compile Ruby and Jemalloc for that distribution.

## Utility environment

A special Docker image is `environments/utility/`, which is used by scripts that perform work that's not related to any specific distribution. These scripts may require certain tools, but because we follow [the "minimal dependencies" principle](minimal-dependencies-principle.md) we don't want to require users to install such tools on their local machines. So we install these tools in the `utility` image, and perform the bulk of the work in the context of such a container.

For example: `build-common-deb` builds the fullstaq-ruby-common Debian package (see [Package organization](package-organization.md)). This scripts requires `dpkg` and FPM to be installed. The `utility` image has both of these installed.

## Environment do not contain scripts

None of the build environment images contain scripts. They only contain dependencies and tools required by scripts. We run environments by:

 1. Creating a container from that build environment's image.
 2. Having that container mount the Fullstaq Ruby's source root.
 3. Telling the container to run a script inside our source tree.

## Mounts

Scripts always run build environment containers in such a way, that insider the container, `/system` is mounted read-only to the source root.

## Versioning

All build environment Docker images are versioned. This is why each `environments/*/` directory has a file `image_tag`. This tag must be bumped every time we make a change to an image. All scripts, which delegate their work to a build environment, read that build environment's `image_tag` file, and runs the Docker container based on an image with that tag.
