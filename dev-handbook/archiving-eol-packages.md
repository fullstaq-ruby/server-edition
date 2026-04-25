# Archiving EOL packages

This document describes how to archive packages for end-of-life (EOL) distributions and prune EOL Ruby versions from the repositories. This is a routine maintenance task that frees CI disk space and keeps the repository lean.

## Background

The CI publish step downloads the full Aptly state archive (`state.tar.zst`) from Google Cloud Storage on every run. This archive grows with every distribution and Ruby version ever published. When distributions or Ruby versions reach EOL, their packages remain in the state archive indefinitely, consuming disk space on GitHub Actions runners.

To address this, we maintain **archive repositories** alongside the main repositories:

| Repository | Bucket | Domain | Purpose |
|------------|--------|--------|---------|
| APT (main) | `fsruby-server-edition-apt-repo` | `apt.fullstaqruby.org` | Current, supported packages |
| APT (archive) | `fsruby-server-edition-apt-repo-archive` | `apt-archive.fullstaqruby.org` | Frozen packages for EOL distributions |
| YUM (main) | `fsruby-server-edition-yum-repo` | `yum.fullstaqruby.org` | Current, supported packages |
| YUM (archive) | `fsruby-server-edition-yum-repo-archive` | `yum-archive.fullstaqruby.org` | Frozen packages for EOL distributions |

Archive repositories are static — CI never writes to them. They use the same versioned bucket structure as the main repos. Each migration creates a new version that merges newly-archived distros with the existing archive contents, so the archive grows incrementally over time.

This pattern follows the precedent set by [PostgreSQL](https://apt-archive.postgresql.org/) (`apt-archive.postgresql.org`) and [HashiCorp](https://www.hashicorp.com/en/blog/announcing-the-linux-package-archive-site) (`archive.releases.hashicorp.com`).

## Two types of cleanup

There are two independent axes of cleanup, each with its own script:

### 1. Distro archival — moving entire EOL distribution repos

When a Linux distribution reaches EOL, we stop building packages for it and move its existing packages to the archive. Users on EOL distributions can still install packages by pointing at the archive repo.

**Scripts:**
 * `internal-scripts/ci-cd/archive/migrate-apt-to-archive.rb`
 * `internal-scripts/ci-cd/archive/migrate-yum-to-archive.rb`

### 2. Package pruning — removing EOL Ruby version packages

When a Ruby version reaches EOL, we stop building it (by removing it from `config.yml`), but its packages persist inside every distro's repository. Pruning removes these stale packages from the still-supported distro repos to reduce state size.

**Scripts:**
 * `internal-scripts/ci-cd/archive/prune-apt-packages.rb`
 * `internal-scripts/ci-cd/archive/prune-yum-packages.rb`

## Removing an EOL distribution

### Step 1: Remove from the build system

 1. Edit `config.yml` and remove the distribution from the `distributions` list (or add it to an exclusion).
 2. Delete the `environments/<distro>/` directory.
 3. Regenerate CI/CD workflows:

    ~~~bash
    ./internal-scripts/generate-ci-cd-yaml.rb
    ~~~

 4. Commit and merge these changes.

### Step 2: Migrate packages to the archive

**Prerequisites:**
 * `gcloud` CLI authenticated with write access to the GCS buckets
 * `az` CLI authenticated with access to the `fsruby2infraowners` Key Vault (for the GPG signing key)
 * `aptly`, `zstd`, and `gpg` installed locally
 * Docker running (for `createrepo_c` in YUM migration)

**Dry run first** to verify which distros will be archived:

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo-archive \
./internal-scripts/ci-cd/archive/migrate-apt-to-archive.rb --dry-run
~~~

The script auto-detects EOL distros by comparing `aptly repo list` output against the distributions defined in `config.yml`. You can also specify distros explicitly:

~~~bash
./internal-scripts/ci-cd/archive/migrate-apt-to-archive.rb --dry-run --distros centos-8,debian-9
~~~

**Execute the migration** (removes `--dry-run`):

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo-archive \
./internal-scripts/ci-cd/archive/migrate-apt-to-archive.rb
~~~

**Repeat for YUM:**

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo-archive \
./internal-scripts/ci-cd/archive/migrate-yum-to-archive.rb --dry-run

PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo-archive \
./internal-scripts/ci-cd/archive/migrate-yum-to-archive.rb
~~~

### Step 3: Restart the web server

After migration, restart the web server so Caddy picks up the new version numbers:

~~~bash
curl -X POST https://apt.fullstaqruby.org/admin/restart_web_server \
  -H "Authorization: Bearer $ID_TOKEN"
~~~

Or restart the Caddy service directly via Ansible/SSH.

### Step 4: Verify

~~~bash
# Archive should list the archived distros
curl -s https://apt-archive.fullstaqruby.org/dists/

# Main repo should only contain supported distros
curl -s https://apt.fullstaqruby.org/dists/

# Verify state archive size decreased
gsutil ls -l gs://fsruby-server-edition-apt-repo/versions/*/state.tar.zst | tail -5
~~~

## Pruning EOL Ruby versions

After removing a Ruby version from `config.yml`, its packages persist in the Aptly state. Run the pruning scripts to remove them.

**Dry run:**

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
./internal-scripts/ci-cd/archive/prune-apt-packages.rb --dry-run
~~~

The script compares packages in the Aptly state against `minor_version_packages` in `config.yml` and identifies any `fullstaq-ruby-X.Y*` packages where `X.Y` is not an active minor version.

**Execute:**

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
./internal-scripts/ci-cd/archive/prune-apt-packages.rb
~~~

**Repeat for YUM:**

~~~bash
PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
./internal-scripts/ci-cd/archive/prune-yum-packages.rb --dry-run

PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
./internal-scripts/ci-cd/archive/prune-yum-packages.rb
~~~

Restart the web server after pruning (same as above).

## Execution order

When performing both distro archival and package pruning in the same session, always run distro archival **first**. This ensures the archive captures the full historical packages for EOL distros before any pruning happens.

 1. `migrate-apt-to-archive.rb`
 2. `prune-apt-packages.rb`
 3. `migrate-yum-to-archive.rb`
 4. `prune-yum-packages.rb`
 5. Restart web server

## Rollback

The versioned bucket structure makes rollback straightforward. Each migration creates a new version — the old version is never modified.

**Revert the main APT repo to a previous version:**

~~~bash
# Find the pre-migration version number
gsutil cat gs://fsruby-server-edition-apt-repo/versions/latest_version.txt

# Point back to the old version
echo -n "OLD_VERSION" | gsutil -h Content-Type:text/plain -h Cache-Control:no-store cp - gs://fsruby-server-edition-apt-repo/versions/latest_version.txt
~~~

**Revert the archive to a previous version:**

~~~bash
gsutil cat gs://fsruby-server-edition-apt-repo-archive/versions/latest_version.txt

echo -n "OLD_VERSION" | gsutil -h Content-Type:text/plain -h Cache-Control:no-store cp - gs://fsruby-server-edition-apt-repo-archive/versions/latest_version.txt
~~~

**Delete all archive contents** (if no users depend on it yet):

~~~bash
gsutil -m rm -r gs://fsruby-server-edition-apt-repo-archive/versions/
~~~

## How the migration scripts work

### APT migration (`migrate-apt-to-archive.rb`)

 1. Downloads the current Aptly state archive from the main bucket.
 2. Identifies EOL distros (published in Aptly but not in `config.yml`).
 3. Fetches the existing archive state (if any) so new distros are merged into it.
 4. Creates or extends the archive Aptly instance with EOL distro data and package pool.
 5. Publishes all archive distros (existing + newly archived).
 6. Drops the EOL distro repos from the main Aptly database.
 7. Runs `aptly db cleanup` to compact the database and reclaim pool space.
 8. Re-publishes remaining distros in the main repo.
 9. Uploads the merged archive as a new archive version (N+1).
 10. Uploads the trimmed state as a new version of the main repo.

### YUM migration (`migrate-yum-to-archive.rb`)

 1. Downloads the current YUM repo from the main bucket via `gsutil rsync`.
 2. Identifies EOL distro directories.
 3. Fetches the existing archive repo (if any) so new distros are merged into it.
 4. Copies EOL distro directories into the local archive copy.
 5. Uploads the merged archive as a new archive version (N+1).
 6. Removes EOL distro directories from the main local copy.
 7. Uploads the trimmed repo as a new version of the main bucket.

### APT pruning (`prune-apt-packages.rb`)

 1. Downloads the Aptly state.
 2. Scans all packages across all distro repos, matching `fullstaq-ruby-X.Y*` against active minor versions.
 3. Removes EOL Ruby packages using `aptly repo remove`.
 4. Compacts, re-publishes, and uploads.

### YUM pruning (`prune-yum-packages.rb`)

 1. Downloads the YUM repo.
 2. Deletes RPM files matching EOL Ruby versions from the filesystem.
 3. Regenerates `repodata/` with `createrepo_c` and re-signs.
 4. Uploads as a new version.
