# poseidon-framework/poseidon-eager: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

### `Added`

- `scripts/source_me.sh`:                Includes various helper functions for all other scripts.
- `scripts/create_eager_input.sh`:       Script to create a preliminary nf-core/eager input TSV from a SSF file.
- `scripts/download_ena_data.py`:        Python script to read SSF file, download FastQs from the ENA, and create a file of expected md5sums.
- `scripts/run_download.sh`:             Wrapper script to submit the FastQ download job to the local MPI-EVA cluster.
- `scripts/validate_downloaded_data.sh`: Script to validate the downloaded data, and create the intended symlinks for running nf-core/eager.
- Added a Changelog: `CHANGELOG.md`
- `scripts/run_eager.sh`:                Script to run nf-core/eager for all packages that need (re-)running.
- `scripts/submit_as_array.sh`:          Helper script for submitting eager jobs as an SGE array on the MPI_EVA cluster.

### `Fixed`

### `Dependencies`

### `Deprecated`
