# Fixing bugs

This guide demonstrates how to analyze and fix bugs. We use [issue #44](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/issues/44) as a case study. We no longer support CentOS 7 or Ruby 2.6 but that doesn't matter for the purpose of learning.

## The bug report

A user reported that, on CentOS 7, s/he is able to install a single Ruby version, but not multiple Ruby versions in parallel. S/he said that this can be reproduced with:

~~~bash
sudo yum install fullstaq-ruby-2.6-jemalloc
sudo yum install fullstaq-ruby-2.7-jemalloc
~~~

Upon installer the latter, s/he ran into the following error:

~~~
Transaction check error:
  file /usr/lib/.build-id/bb/b8242dc9965a6238d9c0f9360487395b95f53b from install of fullstaq-ruby-2.7-jemalloc-rev1-centos7.x86_64 conflicts with file from package fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64
  file /usr/lib/.build-id/bb/b8242dc9965a6238d9c0f9360487395b95f53b.1 from install of fullstaq-ruby-2.7-jemalloc-rev1-centos7.x86_64 conflicts with file from package fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64
~~~

## Step 1: Reproducing the bug locally

The first step is to try to reproduce the bug locally. We start a CentOS 7 container:

~~~bash
docker run -ti --rm centos:7
~~~

Inside the container, we add the Fullstaq Ruby CentOS 7 YUM repo per the [installation instructions](../README.md#rhelcentos).

If we read the reported error message carefully, then we see that the exact package names are as follows:

 * fullstaq-ruby-2.6-jemalloc-rev5-centos7
 * fullstaq-ruby-2.7-jemalloc-rev1-centos7

So we install those exact versions:

~~~bash
yum install fullstaq-ruby-2.6-jemalloc-rev5-centos7
yum install fullstaq-ruby-2.7-jemalloc-rev1-centos7
~~~

And indeed, we run into the same error:

~~~
Transaction check error:
  file /usr/lib/.build-id/bb/b8242dc9965a6238d9c0f9360487395b95f53b from install of fullstaq-ruby-2.7-jemalloc-rev1-centos7.x86_64 conflicts with file from package fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64
  file /usr/lib/.build-id/bb/b8242dc9965a6238d9c0f9360487395b95f53b.1 from install of fullstaq-ruby-2.7-jemalloc-rev1-centos7.x86_64 conflicts with file from package fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64
~~~

So the reproduction was a success!

## Step 2: Research, creating a hypothesis

The next step is to research the error and to create a hypothesis as to why the error occurs.

The error message complains of a conflict between two packages: they both contain these two files:

 * `/usr/lib/.build-id/bb/b8242dc9965a6238d9c0f9360487395b95f53b`.
 * `/usr/lib/.build-id/bb/b8242dc9965a6238d9c0f9360487395b95f53b.1`

The first two questions that come into my mind are:

 1. What is this file for?
 2. Where does this file come from? How did it end up in the package?

### Answering question 1

When we Google for "RPM build-id", we find this Stack Overflow question: [What is the purpose of /usr/lib/.build-id/ dir?](https://unix.stackexchange.com/questions/411727/what-is-the-purpose-of-usr-lib-build-id-dir). Files in the build-id directory contain **debugging information** for executables and libraries. The name of this file equals the hash of the file to which the debugging information belongs.

### Answering question 2

To answer question 2, we investigate the scripts that compile binaries and that generate Ruby RPM packages. As we can see in [Package organization](package-organization) and [Source organization](source-organization.md), the following files are involved in this process:

 * [build-jemalloc](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/build-jemalloc) — Just a wrapper script that delegates the real work to another script. This file is not interesting, so we skip this.
 * [build-ruby](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/build-ruby) — ditto.
 * [build-ruby-rpm](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/build-ruby-rpm) — ditto.
 * [container-entrypoints/build-jemalloc](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/container-entrypoints/build-jemalloc) — This script compiles Jemalloc.
 * [container-entrypoints/build-ruby](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/container-entrypoints/build-ruby) — This script compiles Ruby.
 * [container-entrypoints/build-ruby-rpm](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/container-entrypoints/build-ruby-rpm) — This script turns the Ruby binary tarball into an RPM.

Let's investigate the latter three scripts one by one, by [running them locally](building-packages-locally.md) and inspecting the results.

First, we need to check out the right version of the source tree. At the time the bug was reported, we were on [epic-3.0](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/tree/epic-3.0). So in the fullstaq-ruby-server-edition repo, we checkout that tag:

~~~bash
git checkout epic-3.0
~~~

Next, we download the necessary source code, as described in [Building packages locally, step 1](building-packages-locally.md#step-1-download-source-code). Because [config.yml](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/blob/epic-3.0/config.yml#L28) says that epic-3.0 came with Ruby 2.6.6 and Ruby 2.7.1, we download these Ruby versions' source code.

Next, we compile Jemalloc, for CentOS 7:

~~~bash
./build-jemalloc \
  -n centos-7 \
  -s jemalloc-3.6.0.tar.bz2 \
  -o jemalloc-bin.tar.gz \
  -j 2
~~~

We then inspect the resulting binary tarball. But we see that it doesn't contain any build-id files:

~~~bash
tar -tzf jemalloc-bin.tar.gz | grep build-id
~~~

Next, we compile Ruby 2.6.6 and then 2.7.1, using the exact same parameters that we would use to generate the RPMs that resulted in problems for the reporter:

~~~bash
./build-ruby \
  -n centos-7 \
  -s ruby-2.6.6.tar.gz \
  -v 2.6 \
  -o ruby-bin-2.6.tar.gz \
  -m jemalloc-bin.tar.gz \
  -j 2

./build-ruby \
  -n centos-7 \
  -s ruby-2.7.1.tar.gz \
  -v 2.7 \
  -o ruby-bin-2.7.tar.gz \
  -m jemalloc-bin.tar.gz \
  -j 2
~~~

We then inspect the resulting binary tarballs. But we still don't see any build-id files:

~~~bash
tar -tzf ruby-bin-2.6.tar.gz | grep build-id
tar -tzf ruby-bin-2.7.tar.gz | grep build-id
~~~

Next, we turn the Ruby binary tarballs into RPMs:

~~~bash
./build-ruby-rpm \
  -b ruby-bin-2.6.tar.gz \
  -o fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64.rpm \
  -r 5

./build-ruby-rpm \
  -b ruby-bin-2.7.tar.gz \
  -o fullstaq-ruby-2.7-jemalloc-rev1-centos7.x86_64.rpm \
  -r 1
~~~

We then [inspect the resulting RPM](https://blog.packagecloud.io/eng/2015/10/13/inspect-extract-contents-rpm-packages/):

~~~bash
rpm -qpl fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64.rpm | grep build-id
rpm -qpl fullstaq-ruby-2.7-jemalloc-rev1-centos7.x86_64.rpm | grep build-id
~~~

We see that both RPM files contain build-id files! We conclude that `container-entrypoints/build-ruby-rpm` is the script that creates conflicting files.

### Hypothesis

The answers to questions 1 and 2 raise new questions. Why does `container-entrypoints/build-ruby-rpm` create build-id files? The script only invokes FPM. If we search the FPM manual, it mentions nothing about build-id files.

Furthermore, why would they end up generating a file with the same filename?

Recall that the filename is a hash. So maybe both the Ruby 2.6 and 2.7 packages contain an identical executable file (or library file)? Let's test this hypothesis:

~~~bash
mkdir ruby-bin-2.6 ruby-bin-2.7
tar -C ruby-bin-2.6 -xzf ruby-bin-2.6.tar.gz
tar -C ruby-bin-2.7 -xzf ruby-bin-2.7.tar.gz

# Find duplicate executable files:
# https://unix.stackexchange.com/a/277707
find ruby-bin-2.6 ruby-bin-2.7 ! -empty -type f -perm /u=x -exec md5sum {} + | sort | uniq -w32 -dD
~~~

This outputs:

~~~
16e52eb5129cd6309da2eec81bc749a0  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/ruby/gems/2.6.0/gems/bundler-1.17.2/exe/bundler
16e52eb5129cd6309da2eec81bc749a0  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/ruby/gems/2.7.0/gems/bundler-2.1.4/libexec/bundler
457d8c0fcdca369549cac688d60ec212  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/ruby/gems/2.6.0/gems/rake-12.3.3/exe/rake
457d8c0fcdca369549cac688d60ec212  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/ruby/gems/2.7.0/gems/rake-13.0.1/exe/rake
4dfafb245f3845ac8b7b23913415b102  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/ruby/gems/2.6.0/gems/rdoc-6.1.2/exe/ri
4dfafb245f3845ac8b7b23913415b102  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/ruby/gems/2.7.0/gems/rdoc-6.2.1/exe/ri
5b2809bbc98346a92109c5359ea0c14d  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/libjemalloc_pic.a
5b2809bbc98346a92109c5359ea0c14d  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/libjemalloc_pic.a
74098d8be9935db6ff7492c3c9938e3d  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/libjemalloc.a
74098d8be9935db6ff7492c3c9938e3d  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/libjemalloc.a
7bdc5195b766c12fdd58329652479c0d  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/ruby/gems/2.6.0/gems/rdoc-6.1.2/exe/rdoc
7bdc5195b766c12fdd58329652479c0d  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/ruby/gems/2.7.0/gems/rdoc-6.2.1/exe/rdoc
f860724e97157f0663b60a2f59e2da83  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/libjemalloc.so
f860724e97157f0663b60a2f59e2da83  ruby-bin-2.6/usr/lib/fullstaq-ruby/versions/2.6-jemalloc/lib/libjemalloc.so.1
f860724e97157f0663b60a2f59e2da83  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/libjemalloc.so
f860724e97157f0663b60a2f59e2da83  ruby-bin-2.7/usr/lib/fullstaq-ruby/versions/2.7-jemalloc/lib/libjemalloc.so.1
~~~

Let's examine these files one by one:

 * .../lib/ruby/gems/2.6.0/gems/* — These are Ruby scripts, not real executables. These don't result in debugging information files, so we skip these.
 * .../lib/libjemalloc.a — These are Jemalloc static libraries.
 * .../lib/libjemalloc.so and libjemalloc.so.1 — These are Jemalloc dynamic libraries.

It looks like the Jemalloc binaries are duplicate, and that they're the only things that could cause duplicate build-id files. That makes sense, because we compile Jemalloc only once per distribution, and we reuse the same binaries for building multiple Ruby versions for that same distribution.

## Step 3: Solution

One solution could be to compile Jemalloc separately per Ruby version. That way we won't end up with *exactly* identical Jemalloc binaries (because each compiler invocation produces slightly different output, e.g. by including a timestamp). But I don't think this is a good solution because it makes our build process take longer.

Another solution would be to disable build-id files altogether. For Fullstaq Ruby's use case, we don't care about debugging information anyway. And omitting these files will result in smaller packages.

When we Google for "rpm disable build-id", we find [this Red Hat discussion](https://access.redhat.com/discussions/5045161), which suggests adding the following to the RPM spec file when building the RPM:

~~~
%define _build_id_links none
~~~

But we don't use the RPM building tooling directly. We use FPM, so we have to figure out how to use this with FPM.

When we scan the FPM help output (`fpm --help`), we see that we can use `--rpm-tag` to pass the above to the RPM building tool. So we edit container-entrypoints/build-ruby-rpm and add the following line to the FPM invocation:

~~~
--rpm-tag '%define _build_id_links none' \
~~~

We then rebuild the RPMs, and verify that the build-id files are gone:

~~~bash
./build-ruby-rpm \
  -b ruby-bin-2.6.tar.gz \
  -o fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64.rpm \
  -r 5

rpm -qpl fullstaq-ruby-2.6-jemalloc-rev5-centos7.x86_64.rpm | grep build-id
~~~

The result is [commit 2a17ca0f4493](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/commit/2a17ca0f4493c1ea5738d7d92555337425f7cc43), which not only introduces this fix, but also introduces a test case in order to prevent this problem from reoccurring in the future.
