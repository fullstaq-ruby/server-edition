# ARM64 Build Support

This repository now supports building packages for multiple CPU architectures (currently `amd64` and `arm64`).

## Enabling arm64 in CI

1. Edit `config.yml` and add an `architectures` key:

```yaml
architectures:
  - amd64
  - arm64
```

If omitted, it defaults to only `amd64` to preserve backward compatibility.

2. Regenerate workflow YAML after changing `config.yml` or workflow templates:

```
./internal-scripts/generate-ci-cd-yaml.rb
```

3. Push changes. The GitHub Actions workflows will create per-architecture jobs for:
   - Docker image builds (`Build Docker image [distro/arch]`)
   - Jemalloc builds (`Jemalloc [distro/arch]`)
   - Ruby builds (`Ruby [distro/version/variant/arch]`)
   - Test jobs (`Test [distro/version/variant/arch]`)

Artifacts and package filenames now include the architecture suffix (e.g. `ruby-pkg_3.3_ubuntu-24.04_normal_arm64`).

## Local multi-arch Docker builds

We use `docker buildx` with the implicit `TARGETARCH` build arg. Each architecture image is built separately and stored as its own artifact (not a multi-arch manifest) to keep CI cache logic simple.

## Adding a new architecture

To add another architecture you would need to:

- Extend the `architectures` list in `config.yml`.
- Ensure upstream binary dependencies (sccache, matchhostfsowner) provide downloads for that arch and update the environment Dockerfiles accordingly.
- Potentially adjust any architecture mapping logic in `lib/ci_workflow_support.rb` and packaging scripts.

## Notes / Caveats

- `fullstaq-ruby-common` and `fullstaq-rbenv` packages remain architecture-independent (`all` / `noarch`) and are only built once (amd64 utility image) since their contents are not architecture-specific.
- Jemalloc is built per architecture and distribution; Ruby jemalloc variant jobs depend on the matching architecture artifact.
- RPM dependency autodetection relies on `objdump` inside the utility container. The base image includes binutils with multi-architecture support which is sufficient for `aarch64`.

## Troubleshooting

If an arm64 job fails early with `Unsupported TARGETARCH`, verify the GitHub Actions runner supports that architecture build (GitHub-hosted `ubuntu-24.04` runners currently set `TARGETARCH=amd64`). For true native arm64 builds you may need to enable GitHub's `ubuntu-24.04-arm64` runners or rely on QEMU emulation via `buildx` (current setup uses `--load` which requires a single-platform build; for emulation ensure `binfmt` is installed, which is already present on hosted runners).

