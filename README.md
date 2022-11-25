# Fullstaq Ruby Server Edition: a server-optimized Ruby distribution

Fullstaq Ruby is a Ruby distribution that's optimized for use in servers. It is the easiest way to:

 * Install Ruby on servers — we supply precompiled binaries.
 * Keep Ruby security-patched or up-to-date — integrates with your OS package manager.
 * Significantly reduce memory usage of your Ruby apps — a memory reduction of 50% is quite realistic.
 * Increase performance — thanks to the usage of better memory allocators.

You can think of Fullstaq Ruby as a competitor of `apt/yum install ruby`, `rbenv install` and `rvm install`. We supply [native OS packages](#how-it-works) for various Ruby versions, which are optionally compiled with [Jemalloc](#what-is-jemalloc-and-how-does-it-benefit-me) or [malloc_trim](#what-is-malloc_trim-and-how-does-it-benefit-me), allowing for lower memory usage and potentially increased performance. Our [packaging method](#minor_version_packages) allows much easier security patching.

> Fullstaq Ruby is a work-in-progress! Features like editions optimized for containers and Heroku, better system integration, and much more, are planned. Please see [our roadmap](https://github.com/fullstaq-labs/fullstaq-ruby-umbrella/projects).

**Table of contents:**

 * [Key features](#key-features)
 * [Background](#background)
   - [Why was Fullstaq Ruby created?](#why-was-fullstaq-ruby-created)
   - [Who is behind Fullstaq Ruby?](#who-is-behind-fullstaq-ruby)
 * [How it works](#how-it-works)
   - [Package organization](#package-organization)
   - [Rbenv integration](#rbenv-integration)
   - [Minor version packages: a great way to keep Ruby security-patched](#minor-version-packages-a-great-way-to-keep-ruby-security-patched)
   - [About variants](#about-variants)
   - [Comparisons to other systems](#comparisons-to-other-systems)
     + [Vs RVM and Rbenv](#vs-rvm-and-rbenv)
     + [Vs Ruby packages included in operating systems' official repositories](#vs-ruby-packages-included-in-operating-systems-official-repositories)
     + [Vs the Brightbox PPA](#vs-the-brightbox-ppa)
     + [Vs JRuby, TruffleRuby and Rubinius](#vs-jruby-truffleruby-and-rubinius)
     + [Vs LD_PRELOADing Jemalloc yourself](#vs-ld_preloading-jemalloc-yourself)
 * [Installation](#installation)
   - [Enterprise Linux](#enterprise-linux)
   - [Debian/Ubuntu](#debianubuntu)
   - [Deactivate Git-based Rbenv](#deactivate-git-based-rbenv)
   - [Activate Rbenv shell integration (optional)](#activate-rbenv-shell-integration-optional)
     + [System-wide shell integration](#system-wide-shell-integration)
 * [Usage after installation](#usage-after-installation)
   - [Using a specific Ruby version](#using-a-specific-ruby-version)
   - [Usage with Rbenv](#usage-with-rbenv)
   - [Installing gems and root privileges](#installing-gems-and-root-privileges)
     + [Installing gems system-wide with sudo](#installing-gems-system-wide-with-sudo)
     + [Installing gems without root privileges](#installing-gems-without-root-privileges)
   - [Passenger for Nginx/Apache integration](#passenger-for-nginxapache-integration)
   - [Puma, Unicorn or Passenger Standalone integration](#puma-unicorn-or-passenger-standalone-integration)
   - [Capistrano integration](#capistrano-integration)
 * [FAQ](#faq)
   - [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me)
   - [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)
   - [Is Fullstaq Ruby faster than regular Ruby (MRI)?](#is-fullstaq-ruby-faster-than-regular-ruby-mri)
   - [Why does Fullstaq Ruby integrate with Rbenv?](#why-does-fullstaq-ruby-integrate-with-rbenv)
   - [I do not need multiple Rubies (and have no need for Rbenv), is Fullstaq Ruby suitable for me?](#i-do-not-need-multiple-rubies-and-have-no-need-for-rbenv-is-fullstaq-ruby-suitable-for-me)
   - [Which variant should I pick?](#which-variant-should-i-pick)
   - [Why a new distribution? Why not contribute to Ruby core?](#why-a-new-distribution-why-not-contribute-to-ruby-core)
   - [Will Fullstaq Ruby become paid in the future?](#will-fullstaq-ruby-become-paid-in-the-future)
   - [I am wary of vendor lock-in or that I will become dependent on a specific party for supplying packages. What is Fullstaq Ruby's take on this?](#i-am-wary-of-vendor-lock-in-or-that-i-will-become-dependent-on-a-specific-party-for-supplying-packages-what-is-fullstaq-rubys-take-on-this)
 * [Contributing](#contributing)
 * [Community — getting help, reporting issues, proposing ideas](#community--getting-help-reporting-issues-proposing-ideas)


---

## Key features

 * **Precompiled binaries: save time and energy, increase security**

   Stop wasting time and energy with compiling Ruby or applying source patches. We supply precompiled Ruby binaries so that you don't have to. Improve security by eliminating the need to install a compiler on your server.

 * **Native OS packages: install and update with tools you already use**

   We supply our binaries as [_native OS packages_](#how-it-works) (e.g. via APT, YUM). Easily integrate with your configuration management tools, no need to integrate yet another installer. Easily keep Ruby security-patched or up-to-date with tools you already use.

 * **Jemalloc and `malloc_trim` integration: reduce memory usage, increase performance**

   > Main articles:
   > - [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me)
   > - [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)
   > - [Is Fullstaq Ruby faster than regular Ruby (MRI)?](#is-fullstaq-ruby-faster-than-regular-ruby-mri)

   In Hongli Lai's research project [What Causes Ruby Memory Bloat?](https://www.joyfulbikeshedding.com/blog/2019-03-14-what-causes-ruby-memory-bloat.html), Hongli has identified the OS memory allocator as a major cause of memory bloating in Ruby.

   There are two good solutions for this problem: either by using [the Jemalloc memory allocator](#what-is-jemalloc-and-how-does-it-benefit-me), or by using [the `malloc_trim` API](#what-is-malloc_trim-and-how-does-it-benefit-me).

   Both solutions require patching the Ruby interpreter, but we've done that for you so that you don't have to. Use our binaries, and benefit from reduced memory usage and potentially increased performance out-of-the-box and in a hassle-free manner.

 * **Multiple Ruby versions: ensure compatibility**

   Not all apps are deployed against the latest Ruby — at least, not all the time. We supply binaries for _multiple Ruby versions_. Enjoy the benefits of Fullstaq Ruby no matter which Ruby version you use.

 * **Rbenv integration: manage Ruby versions with already-familiar tools**

   Our multi-Ruby support works by integrating with the popular Ruby version manager [Rbenv](https://github.com/rbenv/rbenv). Continue to benefit from Rbenv ecosystem tooling like [capistrano-rbenv](#capistrano-integration). No need to learn another tool for managing Ruby versions.

## Background

### Why was Fullstaq Ruby created?

Fullstaq Ruby came about for two reasons:

 * **Optimizing for server use cases.**

   Ruby uses a lot of memory. In fact, [way too much and much more than it is "supposed to"](https://www.joyfulbikeshedding.com/blog/2019-03-14-what-causes-ruby-memory-bloat.html). Fortunately, there are "simple" solutions that provide a lot of benefit to users without requiring difficult code changes in Ruby: by compiling Ruby against the [Jemalloc](http://jemalloc.net/) memory allocator, or by modifying Ruby to make use the `malloc_trim` API. In case you use Jemalloc, you even get a nice performance improvement.

   > Main articles:
   > - [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me)
   > - [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)
   > - [Is Fullstaq Ruby faster than regular Ruby (MRI)?](#is-fullstaq-ruby-faster-than-regular-ruby-mri)

   Unfortunately for people who use Ruby in server use cases (e.g. most Ruby web apps), Ruby core developers are a bit careful/conservative and are hesitant to adopt Jemalloc, citing concerns that Jemalloc may cause regressions in non-server use cases, as well as other compatibility-related concerns.

   That's where Fullstaq Ruby comes in: we are opinionated. Fullstaq Ruby does not care about non-server use cases, and we prefer a more progressive approach, so we make choices to optimize for that use case.

 * **Installing the Ruby version you want, and keeping it security-patched, is a miserable experience.**

   The most viable ways to install Ruby are:

    1. From OS repositories, e.g. `apt install ruby`/`yum install ruby`.
    2. Compiling Ruby using a version manager like RVM or Rbenv.
    3. Installing precompiled binaries supplied by RVM or Rbenv.

   All of these approaches have problems:

    + _OS repos drawbacks:_

        - They don't always have the Ruby minor version that you want (or they require you to upgrade your distro to get the version you want).
        - There is no way to install a specific tiny version.
        - Very bad support for managing multiple Ruby versions (e.g. can't easily activate a different Ruby on a per-user or per-project basis).

    + _Compilation via RVM/Rbenv drawbacks:_

        - Requires a compiler, which is a security risk.

    + _RVM/Rbenv (whether compilation or precompiled binaries) drawbacks:_

        - Keeping Ruby security-patched is a hassle.
        - Upgrading to a new Ruby tiny version (e.g. 3.1.0 -> 3.1.1) requires explicit intervention.
        - After upgrading the Ruby tiny version, you need to update all your application servers and deployment code to explicitly use that new version, and you need to reinstall all your gems.

   Fullstaq Ruby addresses all of these problems by combining native OS packages and Rbenv. See [How it works](#how-it-works)

### Who is behind Fullstaq Ruby?

 * Fullstaq Ruby is created by [Hongli Lai](https://www.joyfulbikeshedding.com), CTO at Phusion, author of [the Passenger application server](https://www.phusionpassenger.com/), and creator of the now-obsolete Ruby Enterprise Edition.
 * Fullstaq Ruby is created in partnership with [Fullstaq](https://fullstaq.com/), a cloud native, Kubernetes and DevOps technology partner company in the Netherlands.

If you like this work, please star this repo, follow [@honglilai on Twitter](https://twitter.com/honglilai), and/or [contact Fullstaq](https://fullstaq.com/contact/). Fullstaq can take your technology stack to the next level by providing consultancy, training, and much more.

## How it works

> _See also: [Installation](#installation)_

The Fullstaq Ruby native OS packages allow you to install Rubies by adding our repository and installing them through the OS package manager. The highlights are:

 * **Native OS packages.**

   Rubies are installed by adding our repository and installing through the OS package manager.

 * **We supply packages for each minor version.**

   For example, there are packages for Ruby 3.0 and 3.1. These packages always contain the most recent tiny version. Learn more below in subsection [Minor version packages](#minor_version_packages).

 * **We _also_ supply packages for each tiny version.**

   If you require a very specific tiny version: we support that too! For example we have packages for 3.0.3 and 3.1.0.

 * **3 variants for each Ruby version: normal, jemalloc, malloctrim.**

   Learn more below in subsection [About variants](#about-variants).

 * **Each Ruby installation is just a normal directory.**

   When you install a Ruby package, files are placed in `/usr/lib/fullstaq-ruby/versions/<VERSION>`.

 * **We supply Rbenv as a native OS package.**

   We use Rbenv to switch between different Ruby versions. Rbenv has been slightly modified to support the notion of system-wide Ruby installations.

 * **All Ruby packages register a Ruby version inside the Rbenv system.**

   This registration is done on a system-wide basis (in `/usr/lib/rbenv/versions`, as opposed to `~/.rbenv/versions`).

 * **Parallel packages.**

   All Ruby versions — and all their variants — are installable in parallel.

### Package organization

> _See also: [Installation](#installation)_

Let's say you're on Ubuntu (Enterprise Linux packages use a different naming scheme). Let's pretend Fullstaq Ruby only packages Ruby 3.0.2 and Ruby 3.0.3 (and let's pretend the latter is also the latest release). You will be able to install the following packages:

 * Version 3.0:
    - Normal variant: `apt install fullstaq-ruby-3.0`
    - Jemalloc variant: `apt install fullstaq-ruby-3.0-jemalloc`
    - Malloctrim variant: `apt install fullstaq-ruby-3.0-malloctrim`
 * Version 3.0.2:
    - Normal variant: `apt install fullstaq-ruby-3.0.2`
    - Jemalloc variant: `apt install fullstaq-ruby-3.0.2-jemalloc`
    - Malloctrim variant: `apt install fullstaq-ruby-3.0.2-malloctrim`
 * Version 3.0.3:
    - Normal variant: `apt install fullstaq-ruby-3.0.3`
    - Jemalloc variant: `apt install fullstaq-ruby-3.0.3-jemalloc`
    - Malloctrim variant: `apt install fullstaq-ruby-3.0.3-malloctrim`

All these packages can be installed in parallel. None of them conflict with each other, not even the variants.

### Rbenv integration

Suppose you install all packages listed in the [Package organization](#package-organization) example. That will register Rubies in the system-wide Rbenv versions directory:

 * /usr/lib/rbenv/versions/3.0
 * /usr/lib/rbenv/versions/3.0-jemalloc
 * /usr/lib/rbenv/versions/3.0-malloctrim
 * /usr/lib/rbenv/versions/3.0.2
 * /usr/lib/rbenv/versions/3.0.2-jemalloc
 * /usr/lib/rbenv/versions/3.0.2-malloctrim
 * /usr/lib/rbenv/versions/3.0.3
 * /usr/lib/rbenv/versions/3.0.3-jemalloc
 * /usr/lib/rbenv/versions/3.0.3-malloctrim

These registrations are symlinks. The actual Ruby installation is in `/usr/lib/fullstaq-ruby`. So for example, one symlink looks like this:

    /usr/lib/rbenv/versions/3.0 -> /usr/lib/fullstaq-ruby/versions/3.0

If you run `rbenv versions`, you'll see:

    $ rbenv versions
    * system (set by /home/hongli/.rbenv/version)
      3.0
      3.0-jemalloc
      3.0-malloctrim
      3.0.2
      3.0.2-jemalloc
      3.0.2-malloctrim
      3.0.3
      3.0.3-jemalloc
      3.0.3-malloctrim

Installed Fullstaq Rubies are available to all users on the system. They complement any Rubies that may be installed in `~/.rbenv/versions`.

You activate a specific version by using regular Rbenv commands:

     $ rbenv local 3.0.3
     $ rbenv exec ruby -v
     ruby 3.0.3

     $ rbenv local 3.0.3-jemalloc
     $ rbenv exec ruby -v
     ruby 3.0.3 (jemalloc variant)


<a name="minor_version_packages"></a>

### Minor version packages: a great way to keep Ruby security-patched

`fullstaq-ruby-3.0.2` and `fullstaq-ruby-3.0.3` are **tiny version packages**. They package a specific tiny version.

`fullstaq-ruby-3.0` is a **minor version package**. It always contains the latest tiny version! If today the latest Ruby 3.0 version is 3.0.3, then `fullstaq-ruby-3.0` contains 3.0.3. If tomorrow 3.0.4 is released, then `fullstaq-ruby-3.0` will be updated to contain 3.0.4 instead.

**We recommend installing the minor version package/image over installing tiny version packages/images**:

 * No need to regularly check whether the Ruby developers have released a new tiny versions. The latest tiny version will be automatically installed as part of the regular OS package manager update process (e.g. `apt upgrade`/`yum update`). This is safe because Ruby follows semantic versioning.
 * No need to reinstall all your gems or update any configuration files after a tiny version update has been installed. A minor version package utilizes the same paths, regardless of the tiny version that it contains.

   For example, the `fullstaq-ruby-3.0` package always contains the following, no matter which tiny version it actually is:

    - /usr/lib/rbenv/versions/3.0/bin/ruby
    - /usr/lib/rbenv/versions/3.0/lib/ruby/gems/3.0.0

### About variants

So there are 3 variants: normal, jemalloc, malloctrim. What are the differences?

 - **Normal**: The original Ruby. No third-party patches applied.

   Normal variant packages have no suffix, e.g.: `apt install fullstaq-ruby-3.0.3`

 - **Jemalloc**: Ruby is linked to the Jemalloc memory allocator.

    * Pro: Uses less memory than the original Ruby.
    * Pro: Is usually faster than the original Ruby. (How much faster? [AppFolio benchmark](http://engineering.appfolio.com/appfolio-engineering/2018/2/1/benchmarking-rubys-heap-malloc-tcmalloc-jemalloc), [Ruby Inside benchmark](https://medium.com/rubyinside/how-we-halved-our-memory-consumption-in-rails-with-jemalloc-86afa4e54aa3))
    * Con: May not be compatible with all gems (though such problems should be rare).

   Learn more: [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me)

   Jemalloc variant packages/images have the `-jemalloc` suffix, e.g.: `apt install fullstaq-ruby-3.0.3-jemalloc`

 - **Malloctrim**: Ruby is patched to make use of the `malloc_trim` API to reduce memory usage.

    * Pro: Uses less memory than the original Ruby.
    * Pro: Unlike _jemalloc_, there are no compatibility problems.
    * Con: _May_ be slightly slower. ([How much slower?](https://www.joyfulbikeshedding.com/blog/2019-03-29-the-status-of-ruby-memory-trimming-and-how-you-can-help-with-testing.html))

   Learn more: [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)

   Malloctrim variant packages/images have the `-malloctrim` suffix, e.g.: `apt install fullstaq-ruby-3.0.3-malloctrim`

**Recommendation:** use the _jemalloc_ variant, unless you actually observe compatibility problems.

### Comparisons to other systems

#### Vs RVM and Rbenv

RVM and Rbenv are Ruby version managers. They allow you to install and switch between multiple Ruby versions. They allow installing Ruby by compiling from source, or sometimes by downloading precompiled binaries (the availability of binaries for different platforms is limited).

Fullstaq Ruby is not a Ruby version manager. Fullstaq Ruby is a Ruby distribution: we supply binaries for Ruby. You can think of Fullstaq Ruby as a replacement for `rvm install` and `rbenv install`.

The differences between `rvm/rbenv install` and Fullstaq Ruby are:

 * Fullstaq Ruby is installed via the OS package manager. Rubies installed with `rvm/rbenv install` are not managed via the OS package managers.
 * Fullstaq Ruby updates are supplied through the OS package manager, which can be easily automated. Updates using `rvm/rbenv install` require more effort.
 * When you upgrade Ruby using `rvm/rbenv install`, the path to Ruby and the gem path changes, and so you will need to reinstall all gems and explicit reconfigure application servers to use the upgraded Ruby version -- even if you upgrade to a newer tiny version.

   Fullstaq Ruby supports the concept of [minor version packages](#minor_version_packages), which solves this hassle, making security patching much easier.

 * Fullstaq Ruby provides Ruby [variants with Jemalloc and malloc_trim integration](#about-variants). RVM and Rbenv do not.

   The Jemalloc and malloc_trim variants allow significant reduction in memory usage, and possibly also performance improvements. Learn more: [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me), [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)

   RVM and Rbenv still allow you to apply the Jemalloc and malloc_trim patches, but they don't provide binaries for that (while Fullstaq Ruby does) and so you will be required to compile from source.

#### Vs Ruby packages included in operating systems' official repositories

 * Many operating systems' official repositories only provide a limited number of Ruby versions. If the Ruby version you want isn't available, then you're out of luck: you'll need to upgrade or downgrade the entire OS to get that version, or you need to install it using some other method.

   Fullstaq Ruby provides native OS packages for many more Ruby versions, for multiple OS versions.

 * The Ruby packages provided by many OS repositories also don't allow you to easily switch between versions on a per-user or per-app basis.

   Fullstaq Ruby allows easy switching between versions by integrating with Rbenv.

 * OS repositories package specific minor versions of Ruby. They regularly update their packages to the latest tiny version for that minor package. This is good for security-patching reasons, but if you need to install a specific tiny Ruby version (e.g. for compatibility reasons) then you're out of luck.

   Fullstaq Ruby provides [both minor version packages and specific tiny version packages](#minor_version_packages).

 * Fullstaq Ruby provides [Jemalloc and malloc_trim integration](#about-variants). OS official repositories do not.

   The Jemalloc and malloc_trim variants allow significant reduction in memory usage, and possibly also performance improvements. Learn more: [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me), [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)

#### Vs the Brightbox PPA

The Brightbox PPA is an Ubuntu APT repository provided by [Brightbox](https://www.brightbox.com/).

Like Fullstaq Ruby, the Brightbox PPA contains packages for multiple Ruby versions, for multiple Ubuntu versions.

The differences are:

 * The Brightbox PPA packages specific minor versions of Ruby. They regularly update their packages to the latest tiny version for that minor package. This is good for security-patching reasons, but if you need to install a specific tiny Ruby version (e.g. for compatibility reasons) then you're out of luck.

   Fullstaq Ruby provides [both minor version packages and specific tiny version packages](#minor_version_packages).

 * Fullstaq Ruby provides [Jemalloc and malloc_trim integration](#about-variants). The Brightbox PPA does not.

   The Jemalloc and malloc_trim variants allow significant reduction in memory usage, and possibly also performance improvements. Learn more: [What is Jemalloc and how does it benefit me?](#what-is-jemalloc-and-how-does-it-benefit-me), [What is malloc_trim and how does it benefit me?](#what-is-malloc_trim-and-how-does-it-benefit-me)

 * Fullstaq Ruby also provides Debian, Enterprise Linux packages.

 * Fullstaq Ruby has much better support for managing multiple Ruby versions, thanks to the Rbenv integration.

#### Vs JRuby, TruffleRuby and Rubinius

JRuby, TruffleRuby and Rubinius are alternative Ruby implementations, that are different from the official Ruby (MRI).

Fullstaq Ruby is not an alternative Ruby implementation. It is a distribution of MRI.

#### Vs LD_PRELOADing Jemalloc yourself

You can enjoy reduced memory usage and higher performance with a do-it-yourself solution that involves `LD_PRELOAD`ing Jemalloc. The difference with Fullstaq Ruby is not on a technical level, but on a service level.

With a DIY solution, you are responsible for lifecycle management and for ensuring that the right version of Jemalloc is picked. Only Jemalloc 3 yields reduced memory usage, Jemalloc 5 does not. If you for example install Jemalloc from your distribution's package manager, then you must double-check that your distribution doesn't distribute a too new Jemalloc.

You can of course install Jemalloc from source (assuming you don't mind compiling). But then you become responsible for keeping it security-patched.

Fullstaq Ruby, ensures that the right version of Jemalloc is used. We are a bunch of people that care about this subject, so we are constantly researching better ways to integrate Jemalloc. For example there are some efforts on the way to research how to make use of Jemalloc 5. We also keep an eye on security issues and supply security updates, so that you can sit back and relax.

## Installation

### Enterprise Linux

> Red Hat Enterprise Linux (RHEL) is the original "Enterprise Linux". Compatible derivatives are CentOS, Rocky Linux and Alma Linux.

 * Supported Enterprise Linux versions: 9, 8, 7
 * Supported architectures: x86-64

Add the Fullstaq Ruby repository by creating `/etc/yum.repos.d/fullstaq-ruby.repo`. Pick one of the following:

Enterprise Linux 9:

    [fullstaq-ruby]
    name=fullstaq-ruby
    baseurl=https://yum.fullstaqruby.org/el-9/$basearch
    gpgcheck=0
    repo_gpgcheck=1
    enabled=1
    gpgkey=https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-server-edition/main/fullstaq-ruby.asc
    sslverify=1

Enterprise Linux 8:

    [fullstaq-ruby]
    name=fullstaq-ruby
    baseurl=https://yum.fullstaqruby.org/centos-8/$basearch
    gpgcheck=0
    repo_gpgcheck=1
    enabled=1
    gpgkey=https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-server-edition/main/fullstaq-ruby.asc
    sslverify=1

Enterprise Linux 7:

    [fullstaq-ruby]
    name=fullstaq-ruby
    baseurl=https://yum.fullstaqruby.org/centos-7/$basearch
    gpgcheck=0
    repo_gpgcheck=1
    enabled=1
    gpgkey=https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-server-edition/main/fullstaq-ruby.asc
    sslverify=1

Then install `fullstaq-ruby-common`:

    sudo yum install fullstaq-ruby-common

Ruby packages are now available as `fullstaq-ruby-<VERSION>`:

    $ sudo yum search fullstaq-ruby
    ...
    fullstaq-ruby-3.0.x86_64 : Fullstaq Ruby 3.0
    fullstaq-ruby-3.0-jemalloc.x86_64 : Fullstaq Ruby 3.0-jemalloc
    fullstaq-ruby-3.0-malloctrim.x86_64 : Fullstaq Ruby 3.0-malloctrim
    ...
    fullstaq-ruby-3.1.x86_64 : Fullstaq Ruby 3.1
    fullstaq-ruby-3.1-jemalloc.x86_64 : Fullstaq Ruby 3.1-jemalloc
    fullstaq-ruby-3.1-malloctrim.x86_64 : Fullstaq Ruby 3.1-malloctrim
    ...

You can either install a specific tiny version....

~~~bash
sudo yum install fullstaq-ruby-3.0.3
~~~

...or ([recommended!](#minor_version_packages)) you can install the latest tiny version of a minor release (e.g. the latest Ruby 3.1):

~~~bash
# This will auto-update to the latest tiny version when it's released
sudo yum install fullstaq-ruby-3.1
~~~

You can even install multiple versions in parallel if you really want to:

~~~bash
# Installs the latest 3.1
sudo yum install fullstaq-ruby-3.1

# In parallel, *also* install Ruby 3.1.1
sudo yum install fullstaq-ruby-3.1.1
~~~

**Next steps:**

 - [Deactivate Git-based Rbenv](#deactivate-git-based-rbenv)
 - [Activate Rbenv shell integration (optional)](#activate-rbenv-shell-integration-optional)
 - [Usage after installation](#usage-after-installation)

### Debian/Ubuntu

 * Supported Debian versions: 11 *(bullseye)*, 10 *(buster)*, 9 *(stretch)*
 * Supported Ubuntu versions: 22.04, 20.04, 18.04
 * Supported architectures: x86-64

First, make sure your package manager supports HTTPS and that the necessary crypto tools are installed:

~~~bash
sudo apt install gnupg apt-transport-https ca-certificates curl
~~~

Next, add the Fullstaq Ruby repository by creating `/etc/apt/sources.list.d/fullstaq-ruby.list`. Paste **one** of the lines below depending your distro:

~~~bash
# Ubuntu 22.04
deb https://apt.fullstaqruby.org ubuntu-22.04 main

# Ubuntu 20.04
deb https://apt.fullstaqruby.org ubuntu-20.04 main

# Ubuntu 18.04
deb https://apt.fullstaqruby.org ubuntu-18.04 main

# Debian 11
deb https://apt.fullstaqruby.org debian-11 main

# Debian 10
deb https://apt.fullstaqruby.org debian-10 main

# Debian 9
deb https://apt.fullstaqruby.org debian-9 main
~~~

Then run:

~~~bash
curl -SLfO https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-server-edition/main/fullstaq-ruby.asc
sudo apt-key add fullstaq-ruby.asc
sudo apt update
~~~

Then install `fullstaq-ruby-common`:

    sudo apt install fullstaq-ruby-common

Ruby packages are now available as `fullstaq-ruby-<VERSION>`:

    $ sudo apt search fullstaq-ruby
    ...
    fullstaq-ruby-3.0/ubuntu-22.04 1-ubuntu-22.04 amd64
      Fullstaq Ruby 3.0

    fullstaq-ruby-3.0-jemalloc/ubuntu-22.04 1-ubuntu-22.04 amd64
      Fullstaq Ruby 3.0-jemalloc

    fullstaq-ruby-3.0-malloctrim/ubuntu-22.04 1-ubuntu-22.04 amd64
      Fullstaq Ruby 3.0-malloctrim
    ...
    fullstaq-ruby-3.1/ubuntu-22.04 1-ubuntu-22.04 amd64
      Fullstaq Ruby 3.1

    fullstaq-ruby-3.1-jemalloc/ubuntu-22.04 1-ubuntu-22.04 amd64
      Fullstaq Ruby 3.1-jemalloc

    fullstaq-ruby-3.1-malloctrim/ubuntu-22.04 1-ubuntu-22.04 amd64
      Fullstaq Ruby 3.1-malloctrim
    ...

You can either install a specific tiny version....

    sudo apt install fullstaq-ruby-3.1.1

...or ([recommended!](#minor_version_packages)) you can install the latest tiny version of a minor release (e.g. the latest Ruby 3.1):

~~~bash
# This will auto-update to the latest tiny version when it's released
sudo apt install fullstaq-ruby-3.1
~~~

You can even install multiple versions in parallel if you really want to:

~~~bash
# Installs the latest 3.1
sudo apt install fullstaq-ruby-3.1

# In parallel, *also* install Ruby 3.1.1
sudo apt install fullstaq-ruby-3.1.1
~~~

**Next steps:**

 - [Deactivate Git-based Rbenv](#deactivate-git-based-rbenv)
 - [Activate Rbenv shell integration (optional)](#activate-rbenv-shell-integration-optional)
 - [Usage after installation](#usage-after-installation)

### Deactivate Git-based Rbenv

_Note: you only need to perform this step if you already had a Git-based Rbenv installed. Otherwise you can skip to the next step: [Activate Rbenv shell integration](#activate-rbenv-shell-integration)._

Fullstaq-Ruby relies on a sightly modified version of Rbenv, for which we supply an OS package. This package installs the `rbenv` binary to /usr/bin.

You should modify your shell files to remove your Git-based Rbenv installation from your PATH, so that /usr/bin/rbenv is used instead. For example in your .bash_profile and/or .bashrc, **remove** lines that look like this:

~~~bash
# REMOVE lines like this!
export PATH="$HOME/.rbenv/bin:$PATH"
~~~

There is no need to remove `eval "$(rbenv init -)"`. You're still going to use Rbenv — just one that Fullstaq Ruby provides. More about that in the next step, [Activate Rbenv shell integration](#activate-rbenv-shell-integration).

There is also no need to remove the `~/.rbenv` directory. The Ruby versions installed in there are still supported — *in addition* to system-wide ones installed by the Fullstaq Ruby packages.

### Activate Rbenv shell integration (optional)

_Note: you only need to perform this step if you didn't already have Rbenv shell integration installed. You can skip this step if you already had Rbenv shell integration installed from a previous Git-based Rbenv installation._

For an optimal Rbenv experience, you should activate its [shell integration](https://github.com/rbenv/rbenv#how-rbenv-hooks-into-your-shell).

Run this command, which will tell you to add some code to one of your shell files (like .bashrc or .bash_profile):

    /usr/bin/rbenv init

Be sure to restart your shell after installing shell integration.

#### System-wide shell integration

Adding to .bashrc/.bash_profile only activates the shell integration for that specific user. If you want to activate shell integration for all users, you should add to a system-wide shell file. For example if you're using bash, then:

 * Ubuntu: /etc/bash.bashrc
 * Enterprise Linux: /etc/bashrc

## Usage after installation

### Using a specific Ruby version

Ruby versions are installed to `/usr/lib/fullstaq-ruby/versions/<VERSION>`. Each such directory has a `bin` subdirectory which contains `ruby`, `irb`, `gem`, etc.

Suppose you installed Ruby 3.1 (normal variant). You can execute it directly:

    $ /usr/lib/fullstaq-ruby/versions/3.1/bin/ruby --version
    ruby 3.1.0

    $ /usr/lib/fullstaq-ruby/versions/3.1/bin/gem install --no-document nokogiri
    ...

But for convenience, it's better to add `/usr/lib/fullstaq-ruby/versions/<VERSION>/bin` to your PATH so that you don't have to specify the full path every time. See [Activate Rbenv shell integration (optional)](#activate-rbenv-shell-integration-optional).

### Usage with Rbenv

The recommended way to use Fullstaq Ruby is through the Rbenv integration. You should [learn Rbenv](https://github.com/rbenv/rbenv#readme) if you are not familiar with it. Here is a handy [cheat sheet](https://devhints.io/rbenv).

Suppose you installed Ruby 3.1 (normal variant). You can run that Ruby by setting `RBENV_VERSION` and prefixing yours commands with `rbenv exec`:

    $ export RBENV_VERSION=3.1
    $ rbenv exec ruby --version
    ruby 3.1.0
    $ rbenv exec gem env
    ...

Or, if you've activated the Rbenv shell integration, just running `ruby`, `gem` and various other Ruby would also work, provided that you've activated a certain version and that there's an [Rbenv shim](https://github.com/rbenv/rbenv#understanding-shims) available:

    $ rbenv local 3.1
    $ ruby --version
    ruby 3.1.0
    $ gem env
    ...

### Installing gems and root privileges

By default, gems are installed into a system location (`/usr/lib/fullstaq-ruby/versions/XXX/lib/ruby/gems/XXX`). This means:

 * Gems installed to the system locations are available to all users.
 * When running `gem install` or `bundle install`, root privileges are required.

You can also choose to install gems into a user's home directory, or some other directory that does not require root privileges.

#### Installing gems system-wide with sudo

Be sure to run `gem install` with `sudo`:

~~~bash
# When not using Rbenv
sudo /usr/lib/fullstaq-ruby/versions/XXX/bin/gem install GEM_NAME_HERE

# When using Rbenv
sudo env RBENV_VERSION=XXX rbenv exec gem install GEM_NAME_HERE
~~~

(replace `XXX` with the desired Ruby version and variant for which you want to install the gem)

**When using Bundler, do not prepend sudo**. Bundler will run sudo for you automatically.

#### Installing gems without root privileges

Be sure to run `gem install` with `--user-install`, which will install gems to the user's home directory:

~~~bash
# When not using Rbenv
/usr/lib/fullstaq-ruby/versions/XXX/bin/gem install GEM_NAME_HERE --user-install

# When using Rbenv (assuming you have the shell integration enabled)
gem install GEM_NAME_HERE --user-install
~~~

(replace `XXX` with the desired Ruby version and variant for which you want to install the gem)

When using Bundler, pass `--path` and point it to a user-writable location:

~~~bash
bundle install --path vendor/bundle
~~~

### Passenger for Nginx/Apache integration

First, find out the full path to the Ruby version's binary that you want to use: [Using a specific Ruby version](#using-a-specific-ruby-version).

Next, specify it in the Nginx or Apache config file:

 * Nginx: `passenger_ruby <full path to ruby executable>;`
 * Apache: `PassengerRuby <full path to ruby executable>`

Restart Nginx or Apache after you've made the change.

### Puma, Unicorn or Passenger Standalone integration

First, find out the full path to the Ruby version's binary that you want to use: [Using a specific Ruby version](#using-a-specific-ruby-version).

Next, modify your Puma/Unicorn/Passenger Standalone startup script (e.g. Systemd unit) and make sure that it executes your application server using the full path to your Ruby executable. This is usually done by modifying the `ExecStart` option.

For example suppose you have a Systemd unit file `/etc/systemd/system/puma.service` that looks like this:

~~~ini
# Just an example!

[Unit]
Description=Puma HTTP Server
After=network.target

[Service]
Type=simple
User=app
WorkingDirectory=<YOUR_APP_PATH>
ExecStart=/home/app/.rbenv/versions/3.1.0/bin/ruby -S bundle exec puma -C puma.rb
Restart=always

[Install]
WantedBy=multi-user.target
~~~

Make sure that your `ExecStart` command is prefixed by a call to `/full-path-to-ruby -S`, like this:

~~~ini
ExecStart=/usr/lib/fullstaq-ruby/versions/3.1.0-jemalloc/bin/ruby -S bundle exec puma -C puma.rb
~~~

> Don't forget the `-S`!

Restart your application server after you've made a change, for example `sudo systemctl restart puma`.

### Capistrano integration

If you use Capistrano to deploy your app, then you should use the [capistrano-rbenv](https://github.com/capistrano/rbenv) plugin. Requirements:

 * capistrano-rbenv 2.1.7 or later (due to [pull request #92](https://github.com/capistrano/rbenv/pull/92))
 * Fullstaq Ruby epic 3.3 or later (more info: [issue #47](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/pull/47#issuecomment-634063302))

In your deploy/config.rb make sure you set `rbenv_type` to `:fullstaq`, and `rbenv_ruby` to the Ruby version to you want, possibly with a [variant suffix](#about-variants). Examples:

~~~ruby
set :rbenv_type, :fullstaq


# Use Ruby 3.1 (latest tiny version), normal variant
set :rbenv_ruby, '3.1'

# Use Ruby 3.1.1, normal variant
set :rbenv_ruby, '3.1.1'

# Use Ruby 3.1.1, jemalloc variant
set :rbenv_ruby, '3.1.1-jemalloc'
~~~

## FAQ

### What is Jemalloc and how does it benefit me?

[Jemalloc](http://jemalloc.net/) is the FreeBSD libc memory allocator. It uses a more complex algorithm than the default Linux glibc memory allocator, but is faster and results in less memory fragmentation (which reduces memory usage significantly). Jemalloc has been used successfully by e.g. Firefox and Redis to reduce their memory footprint and ongoing development is supported by Facebook.

### What is malloc_trim and how does it benefit me?

[`malloc_trim()`](http://man7.org/linux/man-pages/man3/malloc_trim.3.html) is an API that is part of the glibc memory allocator. In Hongli Lai's research project [What Causes Ruby Memory Bloat?](https://www.joyfulbikeshedding.com/blog/2019-03-14-what-causes-ruby-memory-bloat.html), Hongli has identified the OS memory allocator as a major cause of memory bloating in Ruby. Luckily, simple fixes exist, and one fix is to invoke `malloc_trim()` which tells the glibc memory allocator to release free memory back to the kernel.

It is found that, if Ruby calls `malloc_trim()` during a garbage collection, then memory usage can be reduced significantly.

However, `malloc_trim` may have some [performance impact](https://www.joyfulbikeshedding.com/blog/2019-03-29-the-status-of-ruby-memory-trimming-and-how-you-can-help-with-testing.html).

### Is Fullstaq Ruby faster than regular Ruby (MRI)?

If you pick the Jemalloc variant, then yes it is often faster. See [About variants](#about-variants). See also these benchmarks:

 * [AppFolio: Benchmarking Ruby's Heap: malloc, tcmalloc, jemalloc
](http://engineering.appfolio.com/appfolio-engineering/2018/2/1/benchmarking-rubys-heap-malloc-tcmalloc-jemalloc)
 * [Ruby Inside: How we halved our memory consumption in Rails with jemalloc](https://medium.com/rubyinside/how-we-halved-our-memory-consumption-in-rails-with-jemalloc-86afa4e54aa3)

### Why does Fullstaq Ruby integrate with Rbenv?

Many users have a need to install and switch between multiple Rubies on a single machine, so we needed a Ruby version manager. Rather than inventing our own, we chose to use Rbenv because it's popular and because it's easy to integrate with.

### I do not need multiple Rubies (and have no need for Rbenv), is Fullstaq Ruby suitable for me?

Yes. The multi-Ruby-support via Rbenv is quite lightweight and is unintrusive, weighting a couple hundred KB at most. Even if you do not need Rbenv, the fact that Fullstaq Ruby uses Rbenv doesn't get in your way and does not meaningfully increase resource utilization.

### Which variant should I pick?

See: [About variants](#about-variants).

### Why a new distribution? Why not contribute to Ruby core?

> _Main article: [What is Fullstaq Ruby's signifiance to the community, and its long-term project vision?](https://www.joyfulbikeshedding.com/blog/2020-05-15-why-fullstaq-ruby.html)_

The Ruby core team is reluctant or slow to incorporate certain changes. And for a good reason: whether a change is an _improvement_ depends on the perspective. The Ruby core team has to care about a wide range of users and use cases. Incorporating Jemalloc or `malloc_trim` is not necessarily an improvement for *all* their users.

While understandable, that attitude does not help users for which those changes *are* actual improvement. Fullstaq Ruby's goal is to help people who use Ruby in a server context, in production environments, on x86-64 Linux. For example we don't care about development environments like macOS, or Raspberry PIs. This allows us to make less conservative choices than the Ruby core team.

Furthermore, the Ruby core team does not want to be responsible for certain aspects, such as distributing binaries. But binaries are valuable. So we take up the responsibility of packaging binaries.

The Ruby core team have debated for years on whether to incorporate Jemalloc, and so far they've only been reluctant. Furthermore, Hongli Lai's research and discussions with various experts have [revealed](https://twitter.com/jashmatthews/status/1140670189954129920) that the only way to make optimal use of Jemalloc is through the `LD_PRELOAD` mechanism: compiling Ruby with `--with-jemalloc` is not enough! `LD_PRELOAD` is such an intrusive and platform-specific change, that we're confident that the Ruby core team will never accept using such a mechanism by default.

In short: Fullstaq Ruby's goal is to bring value to server-production users as soon as possible, and we think maintaining our own distribution is the fastest and best way to achieve that goal.

### Will Fullstaq Ruby become paid in the future?

> _Main article: [What is Fullstaq Ruby's signifiance to the community, and its long-term project vision?](https://www.joyfulbikeshedding.com/blog/2020-05-15-why-fullstaq-ruby.html)_

There will be no paid version. Fullstaq Ruby is fully open source. It is also intended to be a community project where anyone can contribute. There are no monetization plans.

### I am wary of vendor lock-in or that I will become dependent on a specific party for supplying packages. What is Fullstaq Ruby's take on this?

> _Main article: [What is Fullstaq Ruby's signifiance to the community, and its long-term project vision?](https://www.joyfulbikeshedding.com/blog/2020-05-15-why-fullstaq-ruby.html)_

Vendor lock-in is a valid concern that many of us have. It is something we thought about from the beginning and that we *are* addressing.

We have architected our systems in such a way that anyone will be able to build packages themselves. If we ever become slow or defunct, then anyone can easily take matters into own hands. Building Fullstaq Ruby packages from your own systems is so simple that nearly anyone can do it: just install Docker, edit a config file and run a command.

This is achieved by automating the entire build process, and by releasing the making the build tooling as open source. There are almost no manual processes. Please take a look at this repository's source code.

Because Fullstaq Ruby is still a work-in-progress, we don't have documentation yet on how to build packages yourself. Such documentation is [planned](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/issues/1) for [epic 5 of the roadmap](https://github.com/fullstaq-labs/fullstaq-ruby-umbrella/projects).

## Contributing

If you're interested in contributing to Fullstaq Ruby, please check out our [contribution guide](CONTRIBUTING.md) to get started.

## Community — getting help, reporting issues, proposing ideas

To engage with our community, please visit:

 * [The issue tracker](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/issues)
 * [The discussion forum](https://github.com/fullstaq-labs/fullstaq-ruby-server-edition/discussions)
