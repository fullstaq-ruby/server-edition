# Archiving EOL packages

This document describes how to move packages for end-of-life (EOL) distributions and EOL Ruby versions out of the live repositories and into the archive repositories. This is a routine maintenance task that frees CI disk space and keeps the live repositories lean, while keeping EOL packages installable.

## Background

The CI publish step downloads the full Aptly state archive (`state.tar.zst`) from Google Cloud Storage on every run. This archive grows with every distribution and Ruby version ever published. When distributions or Ruby versions reach EOL, their packages remain in the state archive indefinitely, consuming disk space on GitHub Actions runners.

To address this, we maintain **archive repositories** alongside the live repositories:

| Repository | Bucket | Domain | Contents |
|------------|--------|--------|----------|
| APT (live) | `fsruby-server-edition-apt-repo` | `apt.fullstaqruby.org` | Packages whose distribution *and* Ruby version are both supported |
| APT (archive) | `fsruby-server-edition-apt-archive-repo` | `apt-archive.fullstaqruby.org` | Packages whose distribution *or* Ruby version is EOL |
| YUM (live) | `fsruby-server-edition-yum-repo` | `yum.fullstaqruby.org` | Packages whose distribution *and* Ruby version are both supported |
| YUM (archive) | `fsruby-server-edition-yum-archive-repo` | `yum-archive.fullstaqruby.org` | Packages whose distribution *or* Ruby version is EOL |

The live and archive repositories never contain the same package. Packages are moved, never deleted, so EOL packages remain installable from the archive.

The archive only grows: packages are added to it as distributions and Ruby versions reach EOL. It uses the same versioned bucket structure as the live repositories, so each archival run creates a new archive version.

CI never writes to the archive buckets. Packages only enter the archive through the archive scripts described below, run by hand. This is enforced in IAM (see the infra repo's `terraform/repo_buckets.tf`).

This pattern follows the precedent set by [PostgreSQL](https://apt-archive.postgresql.org/) (`apt-archive.postgresql.org`) and [HashiCorp](https://www.hashicorp.com/en/blog/announcing-the-linux-package-archive-site) (`archive.releases.hashicorp.com`).

## What gets archived

Each script decides per package, based on the current `config.yml`:

 * **EOL distribution** — the distribution has a repository in the live repo, but is no longer built (see [Step 1](#step-1-remove-from-the-build-system)). *All* its packages are archived, including `fullstaq-ruby-common` and `fullstaq-rbenv`, and the distribution is removed from the live repo.
 * **EOL Ruby version** — on a supported distribution, any `fullstaq-ruby-X.Y*` package where `X.Y` is not an active minor version (see below). This includes variants (`-jemalloc`, `-malloctrim`) and tiny-version packages (`fullstaq-ruby-X.Y.Z`).

Everything else stays in the live repo. In particular:

 * `fullstaq-ruby-common` and `fullstaq-rbenv` stay on supported distributions.
 * A tiny-version package stays as long as its minor version is active, even if it has been removed from `tiny_version_packages`.
 * A minor version counts as active while it appears in `minor_version_packages` *or* `tiny_version_packages`. So when retiring a Ruby minor version, remove it from both, or nothing for it is archived.

The scripts are:

 * `internal-scripts/ci-cd/archive/archive-apt-packages.rb`
 * `internal-scripts/ci-cd/archive/archive-yum-packages.rb`

Both handle EOL distributions and EOL Ruby versions in the same run, so there is no ordering to get right.

## Procedure

### Step 1: Remove from the build system

For an EOL distribution:

 1. Delete the `environments/<distro>/` directory. With `distributions: all` in `config.yml` (the default), that is what removes a distribution from the build.
 2. If `config.yml` lists distributions explicitly instead, remove it from that list too.

`distribution_exclusions` is not a way to retire a distribution: it only stops particular Ruby versions being built for it.

For an EOL Ruby version:

 1. Edit `config.yml` and remove the version from both `minor_version_packages` and `tiny_version_packages`.

Then:

 1. Regenerate CI/CD workflows:

    ~~~bash
    ./internal-scripts/generate-ci-cd-yaml.rb
    ~~~

 2. Commit and merge these changes.

The scripts read `config.yml` from your working copy, so run them from an up-to-date checkout of `main`.

### Step 2: Announce the change

Users who install an EOL Ruby version, or any package on an EOL distribution, must add the archive repository after this step. Add an entry to the release notes of the next release. For example:

> **Packages for EOL Ruby versions and distributions have moved to the archive repositories.** Packages for Ruby X.Y and for Distro N are no longer available from `apt.fullstaqruby.org` / `yum.fullstaqruby.org`. They remain installable from `apt-archive.fullstaqruby.org` / `yum-archive.fullstaqruby.org`, which use the same signing key. To keep installing them, add the archive repository alongside the regular one:
>
> APT:
>
>     deb https://apt-archive.fullstaqruby.org <distro> main
>
> YUM:
>
>     [fullstaq-ruby-archive]
>     name=fullstaq-ruby-archive
>     baseurl=https://yum-archive.fullstaqruby.org/<distro>/$basearch
>     gpgcheck=0
>     repo_gpgcheck=1
>     enabled=1
>     gpgkey=https://raw.githubusercontent.com/fullstaq-ruby/server-edition/main/fullstaq-ruby.asc
>     sslverify=1

Replace `X.Y`, `Distro N` and `<distro>` with what's being archived. Use the same `Signed-By` option in the APT line as the user's existing Fullstaq Ruby line, if it has one.

### Step 3: Run the archive scripts

**Prerequisites:**

 * `gcloud` CLI authenticated with write access to the live and archive buckets
 * `az` CLI authenticated with access to the `fsruby2infraowners` Key Vault (for the GPG signing key)
 * `aptly`, `zstd` and `gpg` installed locally (for APT)
 * Docker running (for `createrepo_c`, for YUM)
 * Enough free disk space for the full live APT state (roughly 30 GB at the time of writing)

**Dry run first.** A dry run makes every change locally, including the checks described in [How the scripts work](#how-the-scripts-work), and prints the list of packages it would move, but uploads nothing. It still takes the lock and downloads the full live state:

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-apt-archive-repo \
./internal-scripts/ci-cd/archive/archive-apt-packages.rb --dry-run
~~~

Review the list. Then run for real:

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-apt-archive-repo \
./internal-scripts/ci-cd/archive/archive-apt-packages.rb
~~~

Repeat for YUM:

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-yum-archive-repo \
./internal-scripts/ci-cd/archive/archive-yum-packages.rb --dry-run

PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-yum-archive-repo \
./internal-scripts/ci-cd/archive/archive-yum-packages.rb
~~~

The scripts hold the live repo's lock (`locks/apt` or `locks/yum`) for the whole run, which can take an hour for APT. A CI publish waits at most 5 minutes for the lock, then fails. **Don't merge to `main` or re-run CI publishing during an archival run.** If a publish fails this way, re-run it afterwards.

### Step 4: Restart the web server

Caddy only reads repo version numbers at startup, and nothing restarts it after a manual archival run. Until it restarts, the live domains keep serving the pre-archival version and the archive domains keep serving the previous archive version (`versions/0/` on the first run, which returns 404).

The `/admin/restart_web_server` endpoint only accepts OIDC tokens from GitHub-hosted runners in this repo's `deploy` environment, so it can't be called by hand. Restart Caddy over SSH on the backend server instead:

~~~bash
sudo systemctl restart caddy

# Confirm the new versions are loaded
sudo cat /etc/caddy/env-repo-versions
~~~

### Step 5: Verify

~~~bash
# Archive should serve the archived distributions
curl -fsS https://apt-archive.fullstaqruby.org/dists/<distro>/Release
curl -fsS https://yum-archive.fullstaqruby.org/<distro>/x86_64/repodata/repomd.xml

# Live repo should no longer list EOL packages
curl -fsS https://apt.fullstaqruby.org/dists/<distro>/main/binary-amd64/Packages | grep '^Package: fullstaq-ruby-X.Y'

# State archive size should have decreased
gsutil ls -l gs://fsruby-server-edition-apt-repo/versions/*/state.tar.zst | tail -5
~~~

## Rollback

Each run creates a new version of both repositories. Old versions are never modified, so rolling back means pointing `latest_version.txt` back at the previous version and restarting Caddy.

**Revert the live repo:**

~~~bash
gsutil cat gs://fsruby-server-edition-apt-repo/versions/latest_version.txt

echo -n "OLD_VERSION" | gsutil -h Content-Type:text/plain -h Cache-Control:no-store cp - gs://fsruby-server-edition-apt-repo/versions/latest_version.txt
~~~

**Revert the archive:**

~~~bash
gsutil cat gs://fsruby-server-edition-apt-archive-repo/versions/latest_version.txt

echo -n "OLD_VERSION" | gsutil -h Content-Type:text/plain -h Cache-Control:no-store cp - gs://fsruby-server-edition-apt-archive-repo/versions/latest_version.txt
~~~

Revert the live repo, not only the archive: reverting only the archive makes the moved packages unavailable from both.

The same commands apply to the YUM buckets.

## How the scripts work

Both scripts follow the same sequence:

 1. Take the live repo's lock.
 2. Download the latest live repo version.
 3. Decide which packages to move (see [What gets archived](#what-gets-archived)).
 4. Download the latest archive version, if any.
 5. Add the packages to the local archive copy and remove them from the local live copy.
 6. Regenerate the signed metadata of every distribution in both copies, not only the ones that changed.
 7. **Verify** that the archive's metadata lists every package being moved, and that the live repo's metadata lists none of them. The script aborts here, before uploading anything, if either check fails.
 8. Upload the archive as version M+1 and activate it.
 9. Upload the live repo as version N+1 and activate it.

The archive is activated before the live repo, so the moved packages are always available from at least one of them. Before activating each version, the script checks that it still holds the lock.

**Reruns are safe.** If a run fails after step 9, rerun the script:

 * packages already in the archive are skipped or re-added without change;
 * the live repo is then trimmed as normal.

A run with nothing to archive exits without uploading anything.

### APT specifics

 * Packages are added to the archive's Aptly instance individually, with `aptly repo add -force-replace` using the `.deb` files from the live state's pool. Only the moved packages' files end up in the archive's pool.
 * EOL Ruby packages are removed from live with `aptly repo remove`. EOL distributions are unpublished and dropped with `aptly publish drop` and `aptly repo drop`.
 * Both instances run `aptly db cleanup`, so unreferenced files leave the pool.
 * Like `publish-debs.rb`, the state archive (`state.tar.zst`) is created *before* publishing, so it contains no publications and an empty `repo/` directory. `publish-debs.rb` creates publications without dropping existing ones, so it would fail on a state that has them. And an uploaded `repo/` would contain symlinks into a temporary directory that no longer exists.
 * Every distribution is republished, because the upload replaces the whole public tree with the local one. A distribution that wasn't republished would disappear from it.
 * Each distribution in the archive is its own Aptly repo and publication, named after the distribution, like in the live repo.

### YUM specifics

 * RPM files are copied into the archive's `<distro>/<arch>/` directory individually. Files already present are skipped.
 * `createrepo_c` (in the utility Docker image) regenerates `repodata/` for every directory that changed, in both repositories, and `repomd.xml` is re-signed with the signing key.
 * EOL distribution directories are deleted from the live copy.

## Testing

`internal-scripts/ci-cd/archive/test/run-tests.sh` runs both scripts against a fake Google Cloud Storage inside a Docker container with the same Aptly, `createrepo_c` and GPG versions CI uses. It seeds live repositories with a supported and an EOL distribution and an active and an EOL Ruby version, then checks that:

 * a dry run uploads nothing;
 * the right packages end up in each repository, and the two never overlap;
 * distributions with nothing to archive are left alone;
 * all metadata is signed;
 * the uploaded state has no publications, and `publish-debs.rb` can still publish afterwards;
 * a second run changes nothing;
 * a rerun after a failure between the archive and live uploads completes correctly;
 * a second archival round keeps previously archived distributions intact.

The seeded state is built the way `publish-debs.rb` builds it. It needs only Docker. It is not run by CI. Run it after changing either script:

~~~bash
./internal-scripts/ci-cd/archive/test/run-tests.sh
~~~
