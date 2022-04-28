# Adding support for a new distribution

All packages are built within [build environments](build-environments.md): Docker containers that are based on the distribution that we want to package for, and that contains all the tooling (such as compilers) that we need. So adding support for a new distribution involves creating a new build environment for that distribution.

## Before you begin

Follow the [Development environment setup](dev-environment-setup.md) instructions. In particular, be sure to setup the Git hooks.

## Step 1: Creating the build environment

Create a new directory `environments/<DISTRO NAME>-<DISTRO VERSION>` (for example `environments/centos-16`). This directory should contain:

 * A `Dockerfile`.

    - Ensure its `FROM` is set to an appropriate image that corresponds to the distribution and version you want to support. For example `FROM centos:16`.
    - Ensure it has a user account named `builder`, and that the Dockerfile's `USER` directive is set to that account.
    - Ensure a C and C++ compiler toolchain is installed.
    - Ensure ccache is installed and configured.
    - Ensure development headers for OpenSSL, zlib, FFI, readline, ncurses and GDBM are installed.

 * An `image_tag`. This file is used for [versioning](build-environments.md#versioning). Since this is a new file, set its contents to `1`.

When done, build this build environment locally by running:

~~~bash
./build-environment-image ${DISTRO_NAME}-${DISTRO_VERSION}
~~~

For example:

~~~bash
./build-environment-image centos-16
~~~

## Step 2: Updating config.yml

In `config.yml`, scroll to the `distributions` section, and add a comment indicating that we support this distribution. This comment doesn't do anything, and is only there for completeness' sake.

## Step 3: Testing the build environment

Test this build environment by:

 1. [Building packages with it](building-packages-locally.md).
 2. [Testing the built packages](testing-packages-locally.md).

## Step 4: Update docs

In README.md under "Installation", add instructions for this new distribution.

## Step 5: Commit and push your changes

Commit and push your changes to the Git repo.
