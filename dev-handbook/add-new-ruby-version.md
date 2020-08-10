# Adding support for a new Ruby version

To add support for a new Ruby version, open `config.yml` and add it to the `ruby` section. Make sure you update both `minor_version_packages` and `tiny_version_packages`.

Under `minor_version_packages`, if you're modifying an existing entry (as opposed to adding a new one), then don't forget to bump the `package_revision`.
