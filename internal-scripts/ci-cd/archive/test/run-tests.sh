#!/bin/bash
# Tests archive-apt-packages.rb and archive-yum-packages.rb against a
# local fake GCS, inside a container with the real Aptly, createrepo_c
# and GPG. Also runs publish-debs.rb against the result, to check that
# CI can still publish afterwards. Not run by CI.
#
# Usage: ./internal-scripts/ci-cd/archive/test/run-tests.sh
set -euo pipefail

SELFDIR=$(dirname "$0")
SELFDIR=$(cd "${SELFDIR}" && pwd)
ROOTDIR=$(cd "${SELFDIR}/../../../.." && pwd)
IMAGE=fsruby-archive-test

if [[ "${INSIDE_ARCHIVE_TEST_CONTAINER:-}" != true ]]; then
    docker build --platform linux/amd64 -q -t "${IMAGE}" "${SELFDIR}" >/dev/null
    exec docker run --rm --platform linux/amd64 \
        -e INSIDE_ARCHIVE_TEST_CONTAINER=true \
        -v "${ROOTDIR}:/src:ro" \
        "${IMAGE}" \
        bash /src/internal-scripts/ci-cd/archive/test/run-tests.sh
fi

# ---- Inside the container ----

WORK=$(mktemp -d)
export FAKE_GCS_ROOT="${WORK}/gcs"
export FAKE_SIGNING_KEY_PATH="${WORK}/signing-key.asc"
export PATH="/src/internal-scripts/ci-cd/archive/test/fake-bin:${PATH}"
export GNUPGHOME="${WORK}/gnupg"
LIVE_APT=fsruby-server-edition-apt-repo
ARCHIVE_APT=fsruby-server-edition-apt-archive-repo
LIVE_YUM=fsruby-server-edition-yum-repo
ARCHIVE_YUM=fsruby-server-edition-yum-archive-repo

FAILURES=0

function header() {
    echo
    echo "===== $* ====="
}

function check() {
    local description="$1"
    shift
    if "$@"; then
        echo "PASS: ${description}"
    else
        echo "FAIL: ${description}"
        FAILURES=$((FAILURES + 1))
    fi
}

function gcs_version() {
    cat "${FAKE_GCS_ROOT}/$1/versions/latest_version.txt"
}

function public_dir() {
    echo "${FAKE_GCS_ROOT}/$1/versions/$(gcs_version "$1")/public"
}

# Package names (Package_Version_Architecture) in a published APT distribution.
function apt_packages() {
    local file
    file="$(public_dir "$1")/dists/$2/main/binary-amd64/Packages"
    [[ -f "${file}" ]] || return 0
    # Field order within a stanza is not fixed, so print at the end of each stanza.
    awk '/^Package:/{p=$2} /^Version:/{v=$2} /^Architecture:/{a=$2} /^$/{if(p)print p"_"v"_"a; p=""} END{if(p)print p"_"v"_"a}' "${file}" | sort
}

# RPM filenames indexed in a published YUM distro/arch directory.
function yum_packages() {
    local repodata
    repodata="$(public_dir "$1")/$2/repodata"
    [[ -d "${repodata}" ]] || return 0
    zcat "${repodata}"/*-primary.xml.gz | { grep -o 'location href="[^"]*"' || true; } | sed 's/.*href="//; s/"$//; s|.*/||' | sort
}

function contains() {
    grep -qx -- "$2" <<<"$1"
}

function lacks() {
    ! grep -qx -- "$2" <<<"$1"
}

function empty() {
    [[ -z "$1" ]]
}

function count_is() {
    [[ "$(grep -c . <<<"$1" || true)" -eq "$2" ]]
}

function apt_signed() {
    local dir
    dir="$(public_dir "$1")/dists/$2"
    gpg --verify "${dir}/Release.gpg" "${dir}/Release" 2>/dev/null
}

function yum_signed() {
    local dir
    dir="$(public_dir "$1")/$2/repodata"
    gpg --verify "${dir}/repomd.xml.asc" "${dir}/repomd.xml" 2>/dev/null
}

# Checks that a state tarball matches what publish-debs.rb produces:
# no publications, and an empty repo/ directory.
function state_is_unpublished() {
    local bucket="$1"
    local dir="${WORK}/state-check"
    rm -rf "${dir}"
    mkdir -p "${dir}"
    zstd -dc "${FAKE_GCS_ROOT}/${bucket}/versions/$(gcs_version "${bucket}")/state.tar.zst" | tar -xC "${dir}"
    printf '{"rootDir":"%s"}' "${dir}" >"${WORK}/state-check.conf"
    [[ -z "$(aptly -config="${WORK}/state-check.conf" publish list -raw)" ]] &&
        [[ -z "$(find "${dir}/repo" -mindepth 1 -print -quit)" ]]
}

header 'Creating signing key'
mkdir -m 700 "${GNUPGHOME}"
gpg -q --batch --passphrase '' --quick-gen-key 'Archive Test <test@example.com>' default default never 2>/dev/null
gpg -q --batch --export-secret-keys --armor >"${FAKE_SIGNING_KEY_PATH}"
KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub/{print $5; exit}')
echo "Key: ${KEY_ID}"

header 'Building fixture packages'
PKGS="${WORK}/pkgs"
mkdir -p "${PKGS}/deb" "${PKGS}/rpm" "${PKGS}/new"

# make_deb NAME VERSION ARCH [DISTRIBUTION] [OUTPUT_DIR]
function make_deb() {
    local name="$1" version="$2" arch="$3" distribution="${4:-}" output_dir="${5:-${PKGS}/deb}"
    local dir="${WORK}/debbuild/${name}_${version}_${arch}"
    mkdir -p "${dir}/DEBIAN"
    printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: Test <test@example.com>\nDescription: test\n' \
        "${name}" "${version}" "${arch}" >"${dir}/DEBIAN/control"
    if [[ -n "${distribution}" ]]; then
        echo "Distribution: ${distribution}" >>"${dir}/DEBIAN/control"
    fi
    dpkg-deb -Zgzip -b "${dir}" "${output_dir}/${name}_${version}_${arch}.deb" >/dev/null
}

function make_rpm() {
    local name="$1" version="$2" release="$3" arch="$4"
    local topdir="${WORK}/rpmbuild/${name}-${version}-${release}"
    mkdir -p "${topdir}/SPECS"
    cat >"${topdir}/SPECS/pkg.spec" <<SPEC
Name: ${name}
Version: ${version}
Release: ${release}
Summary: test
License: MIT
BuildArch: ${arch}
%description
test
%files
SPEC
    rpmbuild -bb --define "_topdir ${topdir}" --define '_build_id_links none' "${topdir}/SPECS/pkg.spec" >/dev/null 2>&1
    find "${topdir}/RPMS" -name '*.rpm' -exec cp {} "${PKGS}/rpm/" \;
}

# DEB distributions:
#   debian-12  supported, has EOL Ruby packages
#   debian-13  supported, nothing to archive
#   debian-10  EOL
# Ruby 3.4 is active, 3.1 is EOL (per config.yml).
for distro in debian-12 debian-10; do
    make_deb fullstaq-ruby-3.4 "9-${distro}" amd64
    make_deb fullstaq-ruby-3.4-jemalloc "9-${distro}" amd64
    make_deb fullstaq-ruby-3.4.1 "0-${distro}" amd64
    make_deb fullstaq-ruby-3.1 "5-${distro}" amd64
    make_deb fullstaq-ruby-3.1-jemalloc "5-${distro}" amd64
    make_deb fullstaq-ruby-3.1.7 "0-${distro}" amd64
done
make_deb fullstaq-ruby-3.4 9-debian-13 amd64
make_deb fullstaq-ruby-common 1.0-0 all
make_deb fullstaq-rbenv 1.1.2-16 all
# New packages for the publish-debs.rb runs.
make_deb fullstaq-ruby-3.4 10-debian-12 amd64 debian-12 "${PKGS}/new"
make_deb fullstaq-ruby-3.4 10-debian-13 amd64 debian-13 "${PKGS}/new"

# RPM distributions:
#   el-9      supported, has EOL Ruby packages
#   centos-8  supported, nothing to archive
#   centos-7  EOL
for distro in el9 centos7; do
    make_rpm fullstaq-ruby-3.4 rev9 "${distro}" x86_64
    make_rpm fullstaq-ruby-3.4-jemalloc rev9 "${distro}" x86_64
    make_rpm fullstaq-ruby-3.1 rev5 "${distro}" x86_64
    make_rpm fullstaq-ruby-3.1-jemalloc rev5 "${distro}" x86_64
    make_rpm fullstaq-ruby-3.1.7 rev0 "${distro}" x86_64
done
make_rpm fullstaq-ruby-3.4 rev9 centos8 x86_64
make_rpm fullstaq-ruby-common 1.0 0 noarch
make_rpm fullstaq-rbenv 1.1.2_16 1 noarch
ls "${PKGS}/deb" "${PKGS}/rpm"

header 'Seeding live APT repository (version 1)'
# Like publish-debs.rb: the state is archived before publishing, so it
# contains no publications.
function seed_apt() {
    local state="${WORK}/seed-apt"
    mkdir -p "${state}/db" "${state}/repo"
    printf '{"rootDir":"%s","FileSystemPublishEndpoints":{"main":{"rootDir":"%s/repo","linkMethod":"symlink","verifyMethod":"md5"}}}' \
        "${state}" "${state}" >"${WORK}/seed-apt.conf"
    local distro
    for distro in debian-12 debian-13 debian-10; do
        aptly -config="${WORK}/seed-apt.conf" repo create "${distro}" >/dev/null
        aptly -config="${WORK}/seed-apt.conf" repo add "${distro}" "${PKGS}"/deb/*"${distro}"*.deb \
            "${PKGS}/deb/fullstaq-ruby-common_1.0-0_all.deb" "${PKGS}/deb/fullstaq-rbenv_1.1.2-16_all.deb" >/dev/null
    done
    local version_dir="${FAKE_GCS_ROOT}/${LIVE_APT}/versions/1"
    mkdir -p "${version_dir}/public"
    tar -C "${state}" -cf - . | zstd -q -T0 >"${version_dir}/state.tar.zst"
    for distro in debian-12 debian-13 debian-10; do
        aptly -config="${WORK}/seed-apt.conf" publish repo -batch -gpg-key="${KEY_ID}" -distribution="${distro}" \
            -origin=Fullstaq-Ruby -label=Fullstaq-Ruby "${distro}" filesystem:main:. >/dev/null
    done
    cp -rL "${state}/repo/." "${version_dir}/public/"
    echo 1 >"${version_dir}/version.txt"
    echo 1 >"${FAKE_GCS_ROOT}/${LIVE_APT}/versions/latest_version.txt"
}
seed_apt

header 'Seeding live YUM repository (version 1)'
function seed_yum() {
    local version_dir="${FAKE_GCS_ROOT}/${LIVE_YUM}/versions/1"
    local distro sanitized dir
    for distro in el-9 centos-8 centos-7; do
        sanitized=${distro//-/}
        dir="${version_dir}/public/${distro}/x86_64"
        mkdir -p "${dir}"
        cp "${PKGS}"/rpm/*"${sanitized}"*.rpm "${PKGS}"/rpm/*.noarch.rpm "${dir}/"
        createrepo_c -q "${dir}"
        gpg -q --batch --yes --detach-sign --armor "${dir}/repodata/repomd.xml"
    done
    echo 1 >"${version_dir}/version.txt"
    echo 1 >"${FAKE_GCS_ROOT}/${LIVE_YUM}/versions/latest_version.txt"
}
seed_yum

# The scripts read config.yml and environments/ from the working copy.
# Use a writable copy so the second round can retire a distribution.
cp -r /src "${WORK}/src"
cd "${WORK}/src"

APT_ENV=(env PRODUCTION_REPO_BUCKET_NAME="${LIVE_APT}" ARCHIVE_REPO_BUCKET_NAME="${ARCHIVE_APT}")
YUM_ENV=(env PRODUCTION_REPO_BUCKET_NAME="${LIVE_YUM}" ARCHIVE_REPO_BUCKET_NAME="${ARCHIVE_YUM}")

function snapshot() {
    (cd "${FAKE_GCS_ROOT}" && find . -type f ! -path '*/locks/*' -exec md5sum {} + | sort -k2)
}

# Runs publish-debs.rb in production mode, as CI does on main, with
# DRY_RUN so it uploads nothing. Fails if it can't publish the state
# the archive script left behind.
function publish_debs_succeeds() {
    env PRODUCTION_REPO_BUCKET_NAME="${LIVE_APT}" TESTING=false OVERWRITE_EXISTING=false DRY_RUN=true CLEANUP=true \
        ./internal-scripts/ci-cd/publish/publish-debs.rb "$1" >"${WORK}/publish-debs.log" 2>&1 ||
        { tail -20 "${WORK}/publish-debs.log"; return 1; }
}

# ---------------------------------------------------------------- APT

header 'APT: dry run uploads nothing'
before=$(snapshot)
"${APT_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-apt-packages.rb --dry-run
check 'dry run leaves fake GCS unchanged' [ "${before}" == "$(snapshot)" ]
check 'dry run leaves no temp dir behind' empty "$(find /tmp -maxdepth 1 -name 'archive-apt*')"

header 'APT: first run'
LIVE_D13_BEFORE=$(apt_packages "${LIVE_APT}" debian-13)
"${APT_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-apt-packages.rb

LIVE_D12=$(apt_packages "${LIVE_APT}" debian-12)
LIVE_D13=$(apt_packages "${LIVE_APT}" debian-13)
ARCH_D12=$(apt_packages "${ARCHIVE_APT}" debian-12)
ARCH_D10=$(apt_packages "${ARCHIVE_APT}" debian-10)
echo "live debian-12:"; sed 's/^/  /' <<<"${LIVE_D12}"
echo "live debian-13:"; sed 's/^/  /' <<<"${LIVE_D13}"
echo "archive debian-12:"; sed 's/^/  /' <<<"${ARCH_D12}"
echo "archive debian-10:"; sed 's/^/  /' <<<"${ARCH_D10}"

check 'live version bumped to 2' [ "$(gcs_version "${LIVE_APT}")" == 2 ]
check 'archive version is 1' [ "$(gcs_version "${ARCHIVE_APT}")" == 1 ]
check 'live debian-12 keeps active Ruby' contains "${LIVE_D12}" fullstaq-ruby-3.4_9-debian-12_amd64
check 'live debian-12 keeps active Ruby variant' contains "${LIVE_D12}" fullstaq-ruby-3.4-jemalloc_9-debian-12_amd64
check 'live debian-12 keeps tiny of active minor' contains "${LIVE_D12}" fullstaq-ruby-3.4.1_0-debian-12_amd64
check 'live debian-12 keeps common' contains "${LIVE_D12}" fullstaq-ruby-common_1.0-0_all
check 'live debian-12 keeps rbenv' contains "${LIVE_D12}" fullstaq-rbenv_1.1.2-16_all
check 'live debian-12 drops EOL Ruby' lacks "${LIVE_D12}" fullstaq-ruby-3.1_5-debian-12_amd64
check 'live debian-12 drops EOL Ruby variant' lacks "${LIVE_D12}" fullstaq-ruby-3.1-jemalloc_5-debian-12_amd64
check 'live debian-12 drops tiny of EOL minor' lacks "${LIVE_D12}" fullstaq-ruby-3.1.7_0-debian-12_amd64
check 'live debian-13 (nothing to archive) still published, unchanged' [ "${LIVE_D13}" == "${LIVE_D13_BEFORE}" ]
check 'live debian-13 Release is signed' apt_signed "${LIVE_APT}" debian-13
check 'live debian-10 no longer published' empty "$(apt_packages "${LIVE_APT}" debian-10)"
check 'archive debian-12 has exactly the EOL Ruby packages' [ "${ARCH_D12}" == "$(printf '%s\n' \
    fullstaq-ruby-3.1-jemalloc_5-debian-12_amd64 fullstaq-ruby-3.1.7_0-debian-12_amd64 fullstaq-ruby-3.1_5-debian-12_amd64 | sort)" ]
check 'archive debian-10 has all 8 packages' count_is "${ARCH_D10}" 8
check 'archive debian-10 has common' contains "${ARCH_D10}" fullstaq-ruby-common_1.0-0_all
check 'archive has no debian-13' empty "$(apt_packages "${ARCHIVE_APT}" debian-13)"
check 'live and archive debian-12 are disjoint' empty "$(comm -12 <(echo "${LIVE_D12}") <(echo "${ARCH_D12}"))"
check 'live debian-12 Release is signed' apt_signed "${LIVE_APT}" debian-12
check 'archive debian-12 Release is signed' apt_signed "${ARCHIVE_APT}" debian-12
check 'archive debian-10 Release is signed' apt_signed "${ARCHIVE_APT}" debian-10
check 'archive pool contains debian-10 debs' [ -n "$(find "$(public_dir "${ARCHIVE_APT}")/pool" -name '*debian-10*.deb')" ]
check 'live pool no longer contains EOL Ruby debs' empty "$(find "$(public_dir "${LIVE_APT}")/pool" -name 'fullstaq-ruby-3.1*')"
check 'live pool no longer contains debian-10 debs' empty "$(find "$(public_dir "${LIVE_APT}")/pool" -name '*debian-10*')"
check 'live state has no publications (like publish-debs)' state_is_unpublished "${LIVE_APT}"
check 'archive state has no publications' state_is_unpublished "${ARCHIVE_APT}"
check 'lock released' [ ! -e "${FAKE_GCS_ROOT}/${LIVE_APT}/locks/apt" ]
check 'no temp dir left behind' empty "$(find /tmp -maxdepth 1 -name 'archive-apt*')"
check 'publish-debs.rb can publish afterwards' publish_debs_succeeds "${PKGS}/new/fullstaq-ruby-3.4_10-debian-12_amd64.deb"

header 'APT: second run is a no-op'
before=$(snapshot)
"${APT_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-apt-packages.rb
check 'second run changes nothing' [ "${before}" == "$(snapshot)" ]

header 'APT: rerun after crash between archive and live upload'
# Simulate: archive version 1 was activated, live upload never happened.
# Roll the live pointer back to version 1 (still intact in the bucket).
echo 1 >"${FAKE_GCS_ROOT}/${LIVE_APT}/versions/latest_version.txt"
rm -rf "${FAKE_GCS_ROOT}/${LIVE_APT}/versions/2"
"${APT_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-apt-packages.rb
check 'archive debian-12 unchanged after rerun' [ "${ARCH_D12}" == "$(apt_packages "${ARCHIVE_APT}" debian-12)" ]
check 'archive debian-10 unchanged after rerun' [ "${ARCH_D10}" == "$(apt_packages "${ARCHIVE_APT}" debian-10)" ]
check 'live debian-12 trimmed after rerun' [ "${LIVE_D12}" == "$(apt_packages "${LIVE_APT}" debian-12)" ]
check 'live debian-13 unchanged after rerun' [ "${LIVE_D13}" == "$(apt_packages "${LIVE_APT}" debian-13)" ]
check 'archive debian-12 still signed after rerun' apt_signed "${ARCHIVE_APT}" debian-12

header 'APT: second archival round (debian-12 reaches EOL)'
# debian-10 is already archived and is not touched this round. Its
# publication must survive being rebuilt from the previous archive state.
mv environments/debian-12 "${WORK}/debian-12-env"
"${APT_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-apt-packages.rb
ARCH2_D12=$(apt_packages "${ARCHIVE_APT}" debian-12)
echo "archive debian-12:"; sed 's/^/  /' <<<"${ARCH2_D12}"
check 'live debian-12 no longer published' empty "$(apt_packages "${LIVE_APT}" debian-12)"
check 'live debian-13 still unchanged' [ "${LIVE_D13}" == "$(apt_packages "${LIVE_APT}" debian-13)" ]
check 'archive debian-12 now has all 8 packages' count_is "${ARCH2_D12}" 8
check 'archive debian-10 unchanged by second round' [ "${ARCH_D10}" == "$(apt_packages "${ARCHIVE_APT}" debian-10)" ]
check 'archive debian-10 still signed' apt_signed "${ARCHIVE_APT}" debian-10
check 'archive debian-12 signed' apt_signed "${ARCHIVE_APT}" debian-12
check 'publish-debs.rb can publish after second round' publish_debs_succeeds "${PKGS}/new/fullstaq-ruby-3.4_10-debian-13_amd64.deb"
mv "${WORK}/debian-12-env" environments/debian-12

# ---------------------------------------------------------------- YUM

header 'YUM: dry run uploads nothing'
before=$(snapshot)
"${YUM_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-yum-packages.rb --dry-run
check 'dry run leaves fake GCS unchanged' [ "${before}" == "$(snapshot)" ]

header 'YUM: first run'
LIVE_C8_BEFORE=$(yum_packages "${LIVE_YUM}" centos-8/x86_64)
"${YUM_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-yum-packages.rb

LIVE_EL9=$(yum_packages "${LIVE_YUM}" el-9/x86_64)
LIVE_C8=$(yum_packages "${LIVE_YUM}" centos-8/x86_64)
ARCH_EL9=$(yum_packages "${ARCHIVE_YUM}" el-9/x86_64)
ARCH_C7=$(yum_packages "${ARCHIVE_YUM}" centos-7/x86_64)
echo "live el-9:"; sed 's/^/  /' <<<"${LIVE_EL9}"
echo "archive el-9:"; sed 's/^/  /' <<<"${ARCH_EL9}"
echo "archive centos-7:"; sed 's/^/  /' <<<"${ARCH_C7}"

check 'live version bumped to 2' [ "$(gcs_version "${LIVE_YUM}")" == 2 ]
check 'archive version is 1' [ "$(gcs_version "${ARCHIVE_YUM}")" == 1 ]
check 'live el-9 keeps active Ruby' contains "${LIVE_EL9}" fullstaq-ruby-3.4-rev9-el9.x86_64.rpm
check 'live el-9 keeps common' contains "${LIVE_EL9}" fullstaq-ruby-common-1.0-0.noarch.rpm
check 'live el-9 keeps rbenv' contains "${LIVE_EL9}" fullstaq-rbenv-1.1.2_16-1.noarch.rpm
check 'live el-9 drops EOL Ruby' lacks "${LIVE_EL9}" fullstaq-ruby-3.1-rev5-el9.x86_64.rpm
check 'live el-9 drops tiny of EOL minor' lacks "${LIVE_EL9}" fullstaq-ruby-3.1.7-rev0-el9.x86_64.rpm
check 'live el-9 has no leftover EOL RPM files' empty "$(find "$(public_dir "${LIVE_YUM}")/el-9" -name 'fullstaq-ruby-3.1*')"
check 'live centos-8 (nothing to archive) unchanged' [ "${LIVE_C8}" == "${LIVE_C8_BEFORE}" ]
check 'live centos-8 repomd is signed' yum_signed "${LIVE_YUM}" centos-8/x86_64
check 'live centos-7 removed' [ ! -e "$(public_dir "${LIVE_YUM}")/centos-7" ]
check 'archive el-9 has exactly the EOL Ruby packages' [ "${ARCH_EL9}" == "$(printf '%s\n' \
    fullstaq-ruby-3.1-jemalloc-rev5-el9.x86_64.rpm fullstaq-ruby-3.1-rev5-el9.x86_64.rpm fullstaq-ruby-3.1.7-rev0-el9.x86_64.rpm | sort)" ]
check 'archive centos-7 has all 7 packages' count_is "${ARCH_C7}" 7
check 'archive has no centos-8' [ ! -e "$(public_dir "${ARCHIVE_YUM}")/centos-8" ]
check 'live and archive el-9 are disjoint' empty "$(comm -12 <(echo "${LIVE_EL9}") <(echo "${ARCH_EL9}"))"
check 'live el-9 repomd is signed' yum_signed "${LIVE_YUM}" el-9/x86_64
check 'archive el-9 repomd is signed' yum_signed "${ARCHIVE_YUM}" el-9/x86_64
check 'archive centos-7 repomd is signed' yum_signed "${ARCHIVE_YUM}" centos-7/x86_64
check 'no nested distro directory in archive' [ ! -e "$(public_dir "${ARCHIVE_YUM}")/centos-7/centos-7" ]
check 'lock released' [ ! -e "${FAKE_GCS_ROOT}/${LIVE_YUM}/locks/yum" ]
check 'no temp dir left behind' empty "$(find /tmp -maxdepth 1 -name 'archive-yum*')"

header 'YUM: second run is a no-op'
before=$(snapshot)
"${YUM_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-yum-packages.rb
check 'second run changes nothing' [ "${before}" == "$(snapshot)" ]

header 'YUM: rerun after crash between archive and live upload'
echo 1 >"${FAKE_GCS_ROOT}/${LIVE_YUM}/versions/latest_version.txt"
rm -rf "${FAKE_GCS_ROOT}/${LIVE_YUM}/versions/2"
"${YUM_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-yum-packages.rb
check 'archive el-9 unchanged after rerun' [ "${ARCH_EL9}" == "$(yum_packages "${ARCHIVE_YUM}" el-9/x86_64)" ]
check 'archive centos-7 unchanged after rerun' [ "${ARCH_C7}" == "$(yum_packages "${ARCHIVE_YUM}" centos-7/x86_64)" ]
check 'live el-9 trimmed after rerun' [ "${LIVE_EL9}" == "$(yum_packages "${LIVE_YUM}" el-9/x86_64)" ]
check 'no nested distro directory after rerun' empty "$(find "${FAKE_GCS_ROOT}/${ARCHIVE_YUM}" -path '*/centos-7/centos-7')"

header 'YUM: second archival round (el-9 reaches EOL)'
mv environments/el-9 "${WORK}/el-9-env"
"${YUM_ENV[@]}" ./internal-scripts/ci-cd/archive/archive-yum-packages.rb
ARCH2_EL9=$(yum_packages "${ARCHIVE_YUM}" el-9/x86_64)
check 'live el-9 removed' [ ! -e "$(public_dir "${LIVE_YUM}")/el-9" ]
check 'live centos-8 still unchanged' [ "${LIVE_C8}" == "$(yum_packages "${LIVE_YUM}" centos-8/x86_64)" ]
check 'archive el-9 now has all 7 packages' count_is "${ARCH2_EL9}" 7
check 'archive centos-7 unchanged by second round' [ "${ARCH_C7}" == "$(yum_packages "${ARCHIVE_YUM}" centos-7/x86_64)" ]
check 'archive el-9 signed' yum_signed "${ARCHIVE_YUM}" el-9/x86_64
mv "${WORK}/el-9-env" environments/el-9

header 'Result'
if [[ "${FAILURES}" -eq 0 ]]; then
    echo 'All checks passed'
else
    echo "${FAILURES} checks failed"
    exit 1
fi
