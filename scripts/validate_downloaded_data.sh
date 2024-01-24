#!/usr/bin/env bash
set -uo pipefail ## Pipefail, complain on new unassigned variables.
VERSION='0.2.2dev'
## Load helper bash functions
source $(dirname ${0})/source_me.sh

function Helptext() {
  echo -ne "\t usage: ${0} [options] <ssf_fn> <download_dir> <package_eager_dir> \n\n"
  echo -ne "This validates that the md5sums for downloaded FastQ files match the ones in the SSF for the package, and creates symlinks for each line in the eager input TSV.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version\t\tPrint version and exit.\n"
}

## Show helptext and exit if no arguments are provided
if [[ ${#@} -eq 0 ]]; then
  Helptext
  exit 0
fi

if [[ ${1} == '-v' || ${1} == '--version' ]]; then
  echo "validate_downloaded_data.sh version: ${VERSION}"
  exit 0
elif [[ ${1} == '-h' || ${1} == '--help' ]]; then
  Helptext
  exit 0
fi

ssf_file=$(readlink -f ${1})
download_dir=$(readlink -f ${2})
package_eager_dir=$(readlink -f ${3})
symlink_dir=${package_eager_dir}/data
md5sum_file="${download_dir}/expected_md5sums.txt"
newest_fastq=$(ls -Art -1 ${download_dir}/*q.gz | tail -n 1) ## Reverse order and tail to avoid broken pipe errors
script_debug_string="[validate_downloaded_data.sh]:"

## Create output directory if it does not exist
mkdir -p ${symlink_dir}

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
errecho -y "${script_debug_string} md5sums OK!"


errecho -y "${script_debug_string} Creating raw data symlinks: ${download_dir} -> ${symlink_dir}"
ssf_header=($(head -n1 ${ssf_file}))

let pid_col=$(get_index_of 'poseidon_IDs' "${ssf_header[@]}")+1
let lib_name_col=$(get_index_of 'library_name' "${ssf_header[@]}")+1
let fastq_col=$(get_index_of 'fastq_ftp' "${ssf_header[@]}")+1
let lib_built_col=$(get_index_of 'library_built' "${ssf_header[@]}")+1

poseidon_ids=()
library_ids=()
let missing_fastq_count=0

while read line; do
  poseidon_id=$(echo "${line}" | awk -F "\t" -v X=${pid_col} '{print $X}')
  lib_name=$(echo "${line}" | awk -F "\t" -v X=${lib_name_col} '{print $X}')
  fastq_fn=$(echo "${line}" | awk -F "\t" -v X=${fastq_col} '{print $X}')
  library_built_field=$(echo "${line}" | awk -F "\t" -v X=${lib_built_col} '{print $X}')
  library_built=$(infer_library_strandedness ${library_built_field} 0)

  ## If there is no FastQ file for this entry, skip it.
  if [[ -z ${fastq_fn} ]]; then
    ## Count the number of entries without a FastQ file
    let missing_fastq_count+=1
    continue
  fi

  ## One set of sequencing data can correspond to multiple poseidon_ids
  for index in $(seq 1 1 $(number_of_entries ';' ${poseidon_id})); do
    row_pid=$(pull_by_index ';' ${poseidon_id} "${index}-1")

    ## Add _ss suffix to sample_name (and later library_id) if single stranded (data never gets merged with double stranded data in eager).
    if [[ "${library_built}" == "single" ]]; then
      strandedness_suffix='_ss'
      row_pid+=${strandedness_suffix}
    else
      strandedness_suffix=''
    fi

    row_lib_id="${row_pid}_${lib_name}${strandedness_suffix}" ## paste poseidon ID with Library ID to ensure unique naming of library results (both with suffix)
    let lane=$(count_instances ${row_lib_id} "${library_ids[@]}")+1
    

    read -r seq_type r1 r1_target r2 r2_target < <(symlink_names_from_ena_fastq ${download_dir} ${symlink_dir} ${row_lib_id}_L${lane} ${fastq_fn})

    ## Symink downloaded data to new naming to allow for multiple poseidon IDs per fastq.
    ## All symlinks are recreated if already existing
    if [[ ${seq_type} == 'SE' ]]; then
      ln -vfs ${r1} ${r1_target}
    elif [[ ${seq_type} == 'PE' ]]; then
      ln -vfs ${r1} ${r1_target}
      ln -vfs ${r2} ${r2_target}
    fi

    ## Keep track of observed values
    poseidon_ids+=(${row_pid})
    library_ids+=(${row_lib_id})
  done

done < <(tail -n +2 ${ssf_file})

## If there are missing FastQ files, warn the user.
if [[ ${missing_fastq_count} -gt 0 ]]; then
  errecho -y "${script_debug_string} There are ${missing_fastq_count} entries in the SSF file without a FastQ file.\n\tThese entries have been ignored."
fi

## Keep track of versions
version_file="$(dirname ${ssf_file})/script_versions.txt"
##    Remove versions from older run if there
grep -v -F -e "$(basename ${0})" -e "source_me.sh for data validation" ${version_file} >${version_file}.new
##    Then add new versions
echo -e "$(basename ${0}):\t${VERSION}" >> ${version_file}.new
echo -e "source_me.sh for data validation:\t${HELPER_FUNCTION_VERSION}" >>${version_file}.new
mv ${version_file}.new ${version_file}
