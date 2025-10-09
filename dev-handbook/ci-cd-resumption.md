# CI/CD system resumption support

Our Github Actions-based CI/CD system performs [a lot of work](build-workflow-management.md), and takes \~45 minutes per run. Sometimes it could fail due to a random error, such as a network issue or a CI job runner that gets stuck. When that happens, we need to re-run the CI run. Unfortunately, Github Actions only supports re-running a CI job from scratch, instead of only failed jobs. Re-running from scratch wastes a lot of time and resources, and a re-run could also fail.

In order to aleviate this problem, we implement the ability to re-run only failed jobs, ourselves. We call this _resumption support_: the ability for the CI to resume where it left off last time.

## How resumption support works

Resumption support works by checking, for each CI job, whether the artifact that that job should produce, already exists. If so, then that job can be skipped.

When you re-run a CI run, Github Actions wipes all previous state (including artifacts). Therefore, we store artifacts primarily in a Google Cloud Storage bucket ([fullstaq-ruby-server-edition-ci-artifacts](https://storage.googleapis.com/fullstaq-ruby-server-edition-ci-artifacts), part of the [infrastructure](https://github.com/fullstaq-labs/fullstaq-ruby-infra)), which isn't wiped before a re-run.

Here's an example artifact URL:

~~~
gs://fullstaq-ruby-server-edition-ci-artifacts/249/rbenv-deb.tar.zst
~~~

Artifacts are stored on a per-CI-run basis. Thus, they always contains the CI run's number. Note that the CI run number does not change even for re-runs.

At the beginning of a CI run, a job named `determine_necessary_jobs` checks which artifacts exist in the Google Cloud Storage bucket, and determines based on that information which other jobs should be run. Here's an example step in that job:

~~~
##### Determine whether Rbenv DEB needs to be built #####
--> Run ./.github/actions/check-artifact-exists
    Checking gs://fullstaq-ruby-server-edition-ci-artifacts/249/rbenv-deb.tar.zst
    Artifact exists
~~~

The `determine_necessary_jobs` job [outputs a variable](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#jobsjobs_idoutputs) that indicate which other jobs should be run:

~~~yaml
determine_necessary_jobs:
  name: Determine necessary jobs
  runs-on: ubuntu-24.04
  outputs:
    necessary_jobs: ${{ steps.check.outputs.necessary_jobs }}
    ...
~~~

The value of this variable is set by `internal-scripts/ci-cd/determine-necessary-jobs/determine-necessary-jobs.rb`. This script sets the variable to a string in the following format:

~~~
;Download Ruby source 2.7.1;Download Rbenv source;...;<MORE JOB NAMES>;...;
~~~

Then, other jobs use an `if` statement which performs a substring match, in order to check whether that particular job should be run:

~~~yaml
download_ruby_source_<%= slug(ruby_version) %>:
  name: Download Ruby source [<%= ruby_version %>]
  runs-on: ubuntu-24.04
  needs:
    - determine_necessary_jobs
  if: contains(needs.determine_necessary_jobs.outputs.necessary_jobs, ';Download Ruby source <%= ruby_version %>;')
~~~
