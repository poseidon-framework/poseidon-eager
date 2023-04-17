#!/usr/bin/env bash
set -uo pipefail ## Pipefail, complain on new unassigned variables.
VERSION='0.1.0dev'
## Load helper bash functions
source $(dirname ${0})/source_me.sh

ssf_file=$(readlink -f ${1})
download_dir=$(readlink -f ${2})
symlink_dir=$(readlink -f ${3})
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

poseidon_ids=()
library_ids=()

while read line; do
  poseidon_id=$(echo "${line}" | awk -F "\t" -v X=${pid_col} '{print $X}')
  lib_name=$(echo "${line}" | awk -F "\t" -v X=${lib_name_col} '{print $X}')
  fastq_fn=$(echo "${line}" | awk -F "\t" -v X=${fastq_col} '{print $X}')

  ## One set of sequencing data can correspond to multiple poseidon_ids
  for index in $(seq 1 1 $(number_of_entries ';' ${poseidon_id})); do
    row_pid=$(pull_by_index ';' ${poseidon_id} "${index}-1")
    row_lib_id="${row_pid}_${lib_name}" ## paste poseidon ID with Library ID to ensure unique naming of library results
    let lane=$(count_instances ${row_lib_id} "${library_ids[@]}")+1
    
    read -r seq_type r1 r1_target r2 r2_target < <(symlink_names_from_ena_fastq ${download_dir} ${symlink_dir} ${row_lib_id}_L${lane} ${fastq_fn})

    echo ${row_pid} ${seq_type} ${r1}
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

## Keep track of versions
version_file="$(dirname ${ssf_file})/script_versions.txt"
##    Remove versions from older run if there
grep -v -F -e "$(basename ${0})" -e "source_me.sh for data validation" ${version_file} >${version_file}.new
##    Then add new versions
echo -e "$(basename ${0}):\t${VERSION}" >> ${version_file}.new
echo -e "source_me.sh for data validation:\t${HELPER_FUNCTION_VERSION}" >>${version_file}.new
mv ${version_file}.new ${version_file}
