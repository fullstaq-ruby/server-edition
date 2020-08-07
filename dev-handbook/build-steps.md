# Build steps

The process of building all Fullstaq Ruby packages is separated in multiple smaller steps. The following diagram describes what all the steps are:

![](build-steps.png)

The black arrows denote dependencies. A dependency exists when the output of a step is used as input by the dependent step.

Each step in the diagram specifies whether the Git repo contains a shell script for executing that step.

Some steps should be executed multiple times:

 * "Build Ruby binaries" should be executed once for every distribution, variant and Ruby version we want to build for.
 * "Build Jemalloc binaries" should be executed once for every distribution we want to build for.
 * "Build Ruby DEB|RPM" should be executed once for every distribution, variant and Ruby version we want to build for.
