# poseidon-framework/poseidon-eager: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.3.0dev - 03/04/2024

### `Added`

- Removed various scripts that have moved to the minotaur-recipes repo.
- `scripts/download_ena_data.py` can now download PE data
- `scripts/minotaur_packager.sh`: 
  - Add option to force package recreation (but not publishing)
  - Add SSF to packages, and versions in README instead of txt file.
- `scripts/populate_janno.py`:
   - Add endogenous, captureType, udg, library_built, accessions, pipeline URL, and Genotype ploidy.
- `scripts/run_eager.sh` & `scripts/download_and_localise_package_files.sh`: Swap to variable for local paths to minotaur resources (more portable).
- Deactivated GA for validation that now moved to other repo. 
- Updated PR template
- Configs now use tagged release for referencing cofs/assets

### `Fixed`

### `Dependencies`

### `Deprecated`

## v0.2.1dev - 02/11/2023

### `Added`

- `scripts/minotaur_packager.sh`:        Script to create poseidon half-packages and fill in janno from eager results
- `scripts/populate_janno.py`:           Script to fill in janno files with poseidon metadata from nf-core eager results.

### `Fixed`

- `scripts/validate_downloaded_data.sh`: Add helptext
- `scripts/run_eager.sh`:                Now uses `big_data` profile
- Updates to templates for packages and configs. These are now defunct as they are pulled from the minotaur-recipes repo, and will be removed in netx release.
- `scripts/download_and_localise_package_files.sh` distinction between symlink dir and package_eager_dir.

### `Dependencies`

- nf-core/eager=2.4.6

### `Deprecated`

## v0.2.0dev - 25/04/2023

### `Added`

- `scripts/source_me.sh`:                Includes various helper functions for all other scripts.
- `scripts/create_eager_input.sh`:       Script to create a preliminary nf-core/eager input TSV from a SSF file.
- `scripts/download_ena_data.py`:        Python script to read SSF file, download FastQs from the ENA, and create a file of expected md5sums.
- `scripts/run_download.sh`:             Wrapper script to submit the FastQ download job to the local MPI-EVA cluster.
- `scripts/validate_downloaded_data.sh`: Script to validate the downloaded data, and create the intended symlinks for running nf-core/eager.
- Added a Changelog: `CHANGELOG.md`
- `scripts/run_eager.sh`:                Script to run nf-core/eager for all packages that need (re-)running.
- `scripts/submit_as_array.sh`:          Helper script for submitting eager jobs as an SGE array on the MPI_EVA cluster.
- Github Issue templates
- Github pull request template
- @delphis-bot makes the template tsv_patch for a package executable.
- @delphis-bot now only triggered on new PR comment, not edits.
- Propagate versions of all config files used in nf-core/eager runs to `config_profile_description`.
- `scripts/download_and_localise_package_files.sh` is a wrapper script that does all the steps of getting a package backbone ready for eagering. Quality of life script for testing, but will be superceded soon.
- Added `scripts/ssf_validator.py`.

### `Fixed`

### `Dependencies`

### `Deprecated`
