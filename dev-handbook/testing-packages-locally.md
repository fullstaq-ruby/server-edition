# Testing packages locally & debugging test failures

We have an automated test suite for testing whether packages work. This guide shows how to run the test suite locally, how to modify the test suite, and how to debug test failures. You can test either packages that you [built yourself](building-packages-locally.md), or packages that were built by the CI system.

Because we follow [the "minimal dependencies" principle](minimal-dependencies-principle.md), you can test packages for any distribution, regardless of which OS or distribution you're running on.

**Table of contents**

 * [What the test suite does](#what-the-test-suite-does)
 * [Prerequisites](#prerequisites)
 * [Preparing the packages](#preparing-the-packages)
 * [Running the test script](#running-the-test-script)
   - [Testing Debian packages](#testing-debian-packages)
   - [Testing an RPM package](#testing-an-rpm-package)
 * [See also](#see-also)

## What the test suite does

A test suite performs roughly the following work:

 * Test whether packages are installable on a clean system.
 * Test whether key files (like the `ruby` binary) are in the right places.
 * Test whether Ruby actually works.
 * Test whether installing gems (including native extensions) works.

A test is supposed to be run inside a Docker container — that corresponds to the distribution that the packages were built for — that has nothing preinstalled. The test suite will take care of installing necessary tools, such as the compiler toolchain.

The test suite sets up a user account called `utility`. Most test commands are run as that user.

Inside the Docker container, the source tree is mounted under /system.

## Prerequisites

Make sure you've [set up the development environment](dev-environment-setup.md) and that you've cloned the Fullstaq Ruby repository:

~~~bash
git clone https://github.com/fullstaq-labs/fullstaq-ruby-server-edition.git
cd fullstaq-ruby-server-edition
~~~

## Preparing the packages

The first step is to either [build](building-packages-locally.md), or download the package files that you want to test. You need three [package types](package-organization.md):

 * `fullstaq-ruby-XXX`
 * `fullstaq-ruby-common`
 * `fullstaq-rbenv`

In case you want to test packages built by the CI system: you can download them from the corresponding Github Actions CI run, under "Artifacts".

## Running the test script

### Testing Debian packages

Run the `./test-debs` script to test Debian packages. Example invocation:

~~~bash
./test-debs \
  -i debian:10 \
  -v jemalloc \
  -r fullstaq-ruby-2.7-jemalloc_0-debian-10_amd64.deb \
  -b fullstaq-rbenv_1.1.2-16-0_all.deb \
  -c fullstaq-ruby-common_1.0-0_all.deb
~~~

Here's what the parameters mean:

 * `-i` — a Docker image to run the tests in. This should be a Linux distribution image that corresponds to the distribution that the package was built for. For example `debian:VERSION` or `ubuntu:VERSION`.
 * `-v` — The variant that the `fullstaq-ruby-XXX` package was built for. One of `normal`, `jemalloc`, `malloctrim`.
 * `-r` — path to the Ruby package.
 * `-b` — path to the Rbenv package.
 * `-c` — path to the common package.

### Testing an RPM package

Run the `./test-rpms` script to test RPM packages. Example invocation:

~~~bash
./test-rpms \
  -i centos:8 \
  -v jemalloc \
  -r fullstaq-ruby-2.7-jemalloc-rev2-centos8.x86_64.rpm \
  -b fullstaq-rbenv-1.1.2-16-0.noarch.rpm \
  -c fullstaq-ruby-common-1.0-0.noarch.rpm
~~~

Here's what the parameters mean:

 * `-i` — a Docker image to run the tests in. This should be a Linux distribution image that corresponds to the distribution that the package was built for. For example `centos:VERSION`.
 * `-v` — The variant that the `fullstaq-ruby-XXX` package was built for. One of `normal`, `jemalloc`, `malloctrim`.
 * `-r` — path to the Ruby package.
 * `-b` — path to the Rbenv package.
 * `-c` — path to the common package.

## See also

[Adding, modifying & debugging tests](modifying-and-debugging-tests.md)
