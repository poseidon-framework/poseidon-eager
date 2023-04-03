#!/usr/bin/env bash
set -uo pipefail ## Pipefail, complain on new unassigned variables.

## Load helper bash functions
source $(dirname ${0})/source_me.sh

ssf_file=$1
download_dir=$2
md5sum_file="${download_dir}/expected_md5sums.txt"
newest_fastq=$(ls -t -1 ${download_dir}/*q.gz | head -n1)
script_debug_string="[validate_downloaded_data.sh]:"

if [[ ! -f ${md5sum_file} ]]; then
  ## If no md5sum file, create md5sum 
  check_fail 1 "${script_debug_string} No md5sum file found. Missing: ${md5sum_file}"
elif [[ ${newest_fastq} -nt ${md5sum_file} ]]; then
  ## Should never trigger, but a good sanity check nonetheless
  check_fail 1 "${script_debug_string} Downloaded data is newer than ${md5sum_file}. Aborting"
else
  errecho -y "${script_debug_string} Checking md5sums in: ${md5sum_file}"
  md5sum --quiet --strict --check ${md5sum_file}
  check_fail $? "${script_debug_string} md5sum validation failed!"
fi

## TODO: Parse SSF file, create symlinks with data, and run patch.sh on TSV to prepare eager input dirs
