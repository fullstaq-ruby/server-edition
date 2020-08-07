# The "minimal dependencies" principle & the use of Docker

Our source code follows the following principles:

 * Users must be able to build packages for any distribution, regardless of which OS or distribution they're running on.
 * All scripts must be usable without requiring the local machine to have anything other than Bash, Ruby and Docker installed.
 * Do not require the user to run `gem install` or `bundle install`.

This means that we do most of our work in Docker containers, so that we can have controlled [build environments](build-environments.md). All other than Bash and Ruby are to be used through Docker containers.

This is why most of the scripts in the root directory are simple wrappers that parse arguments, and then hand off the bulk of the work to a different script, which is run inside a Docker container. For this purpose, we maintain [multiple Docker images](build-environments.md).

Let's look at `build-ruby-deb` for example. This script takes as input a tarball with compiled Ruby binaries, and produces as output a .deb file. [We use FPM](https://www.joyfulbikeshedding.com/blog/2020-08-03-how-debian-packaging-works.html) — which is a Ruby gem — to produce such a .deb file. Instead of telling the user to `gem install fpm`, the `build-ruby-deb` script invokes the `container-entrypoints/build-ruby-deb` script inside the `environments/utility` Docker container. That container has FPM installed.
