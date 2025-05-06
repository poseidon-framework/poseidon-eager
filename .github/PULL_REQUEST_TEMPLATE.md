<!-- Still preliminary. -->

When a new release is made for minotaur, the following steps should be taken:

- Update the CHANGELOG.md to include a description of all changes.
- Add Release date and bump version number to CHANGELOG.md
- If the eager version was changed:
  - [ ] Update the eager version in the [minotaur-recipes repo config temp](https://github.com/poseidon-framework/minotaur-recipes/blob/main/assets/template.config)
  - [ ] Update [Minotaur's MultiQC configuration file](https://github.com/poseidon-framework/poseidon-eager/blob/main/conf/minotaur_multiqc_config.yaml)
    - [ ] Pull the latest MultiQC config from [nf-core/eager](https://github.com/nf-core/eager/blob/master/assets/multiqc_config.yaml)
    - [ ] Apply the required Minotaur tweaks to the config file.
    - [ ] Update the eager version in `scripts/populate_janno.py`
<!-- No longer needed since the `dev` releases are now done.
  - Update the version number in the following files:
  - [ ] scripts/download_and_localise_package_files.sh
  - [ ] scripts/minotaur_packager.sh
  - [ ] scripts/validate_downloaded_data.sh
  - [ ] scripts/run_eager.sh
  - [ ] scripts/populate_janno.py
  - [ ] scripts/download_ena_data.py
-->
- Create new release, release tag, and name.

After the release:

- Update the poseidon-eager release tag used in the [minotaur-recipes repo](https://github.com/poseidon-framework/minotaur-recipes/blob/main/assets/template.config).
