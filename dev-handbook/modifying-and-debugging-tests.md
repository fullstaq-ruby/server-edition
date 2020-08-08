# Adding, modifying & debugging tests

The [test suite](testing-packages-locally.md) consists of the following key scripts. This guide tells you:

 * In which order the scripts are run, which script serves what purpose and in what environment they run. This allows you to know which files you need to modify in order to modify or extend the test suite.
 * How to develop tests in a fast cycle.
 * How to debug the test suite.

**Table of contents**

 * [Test suite phases](#test-suite-phases)
   - [Phase 1: test-{debs,rpms}](#phase-1-test-debsrpms)
   - [Phase 2: container-entrypoints/test-{debs,rpms}-prepare](#phase-2-container-entrypointstest-debsrpms-prepare)
   - [Phase 3: container-entrypoints/test-{debs,rpms}](#phase-3-container-entrypointstest-debsrpms)
   - [Phase 4: internal-scripts/test-{debs,rpms}](#phase-4-internal-scriptstest-debsrpms)
 * [Debugging](#debugging)
 * [Speeding up the test suite development cycle](#speeding-up-the-test-suite-development-cycle)

## Test suite phases

### Phase 1: test-{debs,rpms}

These are simply wrappers that parse arguments, and then delegate most of their work to Docker containers, which then run the other scripts mention in this section.

You only need to modify these scripts when you need to change CLI parameters.

### Phase 2: container-entrypoints/test-{debs,rpms}-prepare

The test script in phase 1, first launches a [utility](build-environments.md) Docker container, in which it runs the corresponding "prepare" script.

This phase 2 script sets up an APT or YUM repo. So that the script in phase 3 can install the package from a local APT/YUM repo.

You usually don't need to modify this phase 2 script.

### Phase 3: container-entrypoints/test-{debs,rpms}

The test script in phase 1 now launches a Docker container (whose image corresponds to the `-i` parameter). Inside the container, it calls the corresponding container-entrypoint script.

This phase 3 script's only responsibility is to do the following, inside said container, in the given order:

 1. Run the script in phase 4.
 2. Open a shell, if `-D` was passed to `./test-{debs,rpms}`. See section [Debugging](#debugging).

You usually don't need to modify this phase 3 script.

### Phase 4: internal-scripts/test-{debs,rpms}

**This is where the main test suite code is located!** This is probably the file you want to modify.

Notes:

 * This script is run as root. But most test commands should be run as the `utility` user. You can use `sudo -u utility -H` for that purpose.
 * You should use the `run` function in order to run commands. This function logs the command to be run, then runs it. This way you don't need to perform a separate "echo" in order to tell the user which command is being run.

## Debugging

If you want to debug the test suite (regardless of whether it fails), then you can pass the `-D` option to the `./test-{debs,rpms}` script in the source root. This way, when the test finishes (regardless of success or failure) it will spawn a Bash shell inside the phase 3 script's Docker container, so that you can poke around and inspect things.

The shell is launched as the `utility` user, which most test commands are run as. If you require root privileges, then use `sudo`, which does not require a password.

Inside the container, the Fullstaq Ruby source tree is mounted under /system.

## Speeding up the test suite development cycle

Running the test suite takes a while. Most of the time is spent on the setup phase, where the test suite installs prerequisite tools inside the container. In order to speed up your development cycle, we recommend the following methodology, which bypasses the installation phase:

 1. Launch a shell inside the test container (see section "Debugging").
 2. Modify `internal-scripts/test-{debs,rpms}` as you see fit.
 3. Test whether the modifications in step 2 works, by running them directly in the shell launched by step 1.

    Caveats to consider:

     - There is no `run` function in the shell, so omit that when running things in the shell.
     - `internal-scripts/test-{debs,rpms}` runs as root, whereas the shell is launched as the `utility` user. If you need root privileges, use sudo.
     - Environment variables set by the phase 4 script, are not available in the shell. If you need them, set them yourself, based on how the phase 4 script does it.

 4. Repeat 2 and 3 until satisfied.
 5. Exit the shell. [Run the entire test suite again](testing-packages-locally.md), to check whether the modifications work.
