# Release checklist

## Preparation

Find out what the previous release's Git tag is (e.g. `epic-1`) and set an environment variable:

    MERGE_BASE=$(git merge-base origin/master HEAD)
    PREV_RELEASE_TAG=$(git describe $MERGE_BASE --tags --abbrev=0)

## Step 1: check whether the Rbenv package revision needs to be changed

Check whether config.yml's `rbenv.ref` has changed since the previous release:

~~~bash
git archive $PREV_RELEASE_TAG config.yml | tar -xO | ruby -ryaml -e 'puts YAML.load(STDIN)["rbenv"]["ref"]'
cat config.yml | ruby -ryaml -e 'puts YAML.load(STDIN)["rbenv"]["ref"]'
~~~

 * If true, then check whether the new Rbenv commit ref changed its version number compared to the previous Fullstaq Ruby release.

    - If true, then reset `rbenv.package_revision` to 0.
    - Otherwise, bump `rbenv.package_revision` if not already done.

 * Otherwise, check whether any of these files have changed in such a way that they would change the Rbenv package contents or metadata:

        git diff $PREV_RELEASE_TAG..HEAD \
            container-entrypoints/build-rbenv-deb \
            container-entrypoints/build-rbenv-rpm

   If true, then bump `rbenv.package_revision` if not already done.

## Step 2: check whether the fullstaq-ruby-common package version or revision needs to be changed

Check whether any of these files have changed in such a way that they would change the fullstaq-ruby-common package's contents or metadata:

    git diff $PREV_RELEASE_TAG..HEAD \
        container-entrypoints/build-common-deb \
        container-entrypoints/build-common-rpm

If true, then bump `common.(deb|rpm).(version|package_revision)` as appropriate (unless already done).

## Step 3: check whether any Ruby package revisions need to be changed

Check whether any of these files have changed in such a way that they would change the package contents or metadata:

    git diff $PREV_RELEASE_TAG..HEAD \
        container-entrypoints/build-jemalloc \
        container-entrypoints/build-ruby \
        container-entrypoints/build-ruby-deb \
        container-entrypoints/build-ruby-rpm

If true, then for all Ruby versions that aren't newly introduced in the next release, bump their package revision number (unless already done).
