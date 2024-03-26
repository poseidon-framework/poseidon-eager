<!-- Still preliminary. -->

When a new release is made for minotaur, the following steps should be taken:

- Update the CHANGELOG.md to include a description of all changes.
- Add Release date and bump version number to CHANGELOG.md
- Update the version number in the following files:
  - [ ] scripts/download_and_localise_package_files.sh
  - [ ] scripts/ssf_validator.py
  - [ ] scripts/create_eager_input.sh
  - [ ] scripts/minotaur_packager.sh
  - [ ] scripts/validate_downloaded_data.sh
  - [ ] scripts/run_eager.sh
  - [ ] scripts/populate_janno.py
  - [ ] scripts/download_ena_data.py
- Create new release, release tag, and name.

After the release:

- Update the poseidon-eager release tag used in the [minotaur-recipes repo](https://github.com/poseidon-framework/minotaur-recipes/blob/main/assets/template.config).
