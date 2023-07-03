# Development environment set up

## Host OS & dependencies

You can develop Fullstaq Ruby on Linux, macOS, or Windows with WSL2. You just need the following things installed:

 * Bash
 * Docker
 * Ruby (any version >= 3.2)

The small number of dependencies is [intentional](minimal-dependencies-principle.md).

## Git hooks

You should also setup our Git hooks, so that on every commit, the Github Workflow file is properly updated from any changes you may make from either its ERB template, or the workflow configuration file. For more info about this, see [Build workflow management](build-workflow-management.md).

To setup the Git hooks, run:

~~~bash
git config core.hooksPath .githooks
~~~
