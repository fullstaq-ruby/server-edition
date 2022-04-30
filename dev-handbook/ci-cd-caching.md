# CI/CD caching

The CI/CD system caches C/C++ compiler invocations using [sccache](https://github.com/mozilla/sccache). Sccache is a C/C++/Rust compiler cacher, similar to [ccache](https://ccache.dev/), but caches to cloud storage instead of the local filesystem.

We used to use ccache, in combination with Github's [cache action](https://github.com/actions/cache) to cache the ccache directory. We had a unique ccache directory on a per-distribution, per-Ruby version and per-variant basis. But each ccache directory can be huge (hundreds of MBs or several GBs). This gave rise to several problems:

 * Because [we build so many different packages](build-workflow-management.md), we easily exceed the Github Actions cache storage limit of 10 GB.
 * Downloading/uploading the entire ccache directory takes a significant amount of time.
 * Ccache may not need to access all files in the ccache directory, so downloading the entire ccache directory can be overkill.
 * Variants have many similarities, and so we should be able to achieve a reasonable cache hit rate if compilations of different variants (given the same distribution and Ruby version) share the same cache. With the ccache approach, cache sharing between different CI jobs is very difficult.
 * CI jobs for Git branches can't warm up the cache for the CI job that will run when the branch is merged to main.

Sccache solves all of the above problems. We cache Azure Blob Storage. All CI jobs access the same Azure Blob Storage container, but we divide that container into multiple separate logical caches by using prefixes (directory names). We assign a unique prefix only on a per-distribution basis. This means that all CI jobs targeting the same distribution can share the same cache, regardless of the Ruby version or variant being compiled, and regardless of the branch.

> Trivia: we [contributed the ability to specify a prefix within Azure Blob Storage](https://github.com/mozilla/sccache/pull/1109) so that we can use sccache in Fullstaq Ruby.

## Why Azure Blob Storage?

The choice of Azure Blob Storage may seem odd given the fact that [the rest of our infrastructure is hosted on Google Cloud](https://github.com/fullstaq-ruby/infra/blob/main/docs/infrastructure-overview.md). The reason is performance. Github-hosted Actions runners are hosted on Azure. [Research has shown](https://github.com/fullstaq-ruby/server-edition/issues/86#issuecomment-1032643774) that latency between Azure and Google Cloud Storage is pretty abysmal: caching to Google Cloud Storage actually makes things **slower**, even if the runner and the Google Cloud Storage bucket are located near each other. In contrast, latency between runners and Azure Blob Storage is very good, even if runners are located on two opposite sides of the US continent.

## Expiration

We expire cache entries based on last access time. Using [lifecycle rules](https://docs.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview#rule-actions), we automatically delete objects that haven't been accessed in 90 days.

Ideally we want LRU expiration based by total cache size, like ccache does. But this approach is not supported by sccache when using Azure Blob Storage (likely because calculating the total cache size is expensive), so last-access-time-based expiration is the next best thing.

## Performance impact

The use of sccache impacts performance as follows (compared to not using sccache):

 * Cold compilations are ~28% slower.
 * Hot compilations are ~56% faster.
