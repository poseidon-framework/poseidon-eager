#!/usr/bin/env bash
VERSION='0.0.1dev'

## Helptext function
function Helptext() {
  echo -ne "\t usage: ${0} [options] Package_name\n\n"
  echo -ne "This script reads the information present in the ena_table of a poseidon package and creates a TSV file that can be used for processing the publicly available data with nf-core/eager.\n\n"
  echo -ne "Options:\n"
  echo -ne "-s, --skip_checksum\tSkip md5sum checking of input data.\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Source helper functions
repo_dir=$(dirname $(readlink -f ${0}))/..  ## The repository will be the original position of this script. If a user copies instead of symlink, this will fail.
source ${repo_dir}/scripts/source_me.sh             ## Source helper functions

## Parse CLI args.
TEMP=`getopt -q -o hvs --long help,version,skip_checksum -n "${0}" -- "$@"`
eval set -- "${TEMP}"

## Parameter defaults
package_name=''
skip_md5='TRUE' #'FALSE'  ## Deactivated for now until decisions about the raw data handling are made.
# root_download_dir='/mnt/archgen/poseidon/raw_sequencing_data'
# root_output_dir='/mnt/archgen/poseidon/raw_sequencing_data/eager'

## Print helptext and exit when no option is provided.
if [[ "${#@}" == "1" ]]; then
  Helptext
  exit 0
fi

## Read in CLI arguments
while true ; do
  case "$1" in
    -s|--skip_checksum) skip_md5='TRUE'; shift ;;
    -h|--help)          Helptext; exit 0 ;;
    -v|--version)       echo ${VERSION}; exit 0;;
    --)                 package_name="${2}"; break ;;
    *)                  echo -e "invalid option provided.\n"; Helptext; exit 1;;
  esac
done

## Throw error if expected positional argument is not there.
if [[ ${package_name} == '' ]]; then
  errecho -r "No package name provided."
  Helptext
  exit 0
fi

package_dir="${repo_dir}/packages/${package_name}"
ena_table="${package_dir}/${package_name}.ssf"
tsv_patch="${package_dir}/tsv_patch.sh"
raw_data_dummy_path='<PATH_TO_DATA>'

## Error if input ssf or directory does not exist
if [[ ! -d ${package_dir} ]]; then
  check_fail 1 "[${package_name}]: Package directory '${package_dir}' does not exist."
fi

if [[ ! -f ${ena_table} ]]; then
  check_fail 1 "[${package_name}]: No sequencingSourceFile found for package. Check that file ${ena_table} exists."
fi

## Read required info from yml file
# package_rawdata_dir="${root_download_dir}/${package_name}"
out_file="${package_dir}/${package_name}.tsv"

## This will all break down if the headers contain whitespace.
ena_table_header=($(head -n1 ${ena_table}))

## TODO Update checksum checking once decisions on raw data handling are made.
## Checksums
if [[ ${skip_md5} != 'TRUE' ]]; then
  errecho -y "[${package_name}] Checking md5sums of downloaded files"
  let fastq_col=$(get_index_of 'fastq_ftp' "${ena_table_header[@]}")+1
  downloaded_md5sums=$(
    tail -n +2 ${ena_table} | \
    awk -F "\t" -v col=${fastq_col} '{print $col}' | \
    while read path; do
      echo "${package_rawdata_dir}/$(basename ${path})"
    done | \
    xargs md5sum |\
    cut -f 1 -d " "
  )

  ## Expected checksums
  let chksm_col=$(get_index_of 'fastq_md5' "${ena_table_header[@]}")+1
  expected_md5sums=$(
    tail -n +2 ${ena_table} | \
    awk -F "\t" -v col=${chksm_col} '{print $col}'
  )

  ## Throw error if there's a mismatch in md5sums. Matches whole set of sums, so if any files are missing, that will also cause errors.
  ## Order is same in both sets otherwise.
  if [[ "${downloaded_md5sums}" != "${expected_md5sums}" ]]; then
    check_fail 1 "md5sum mismatch detected. Please verify FastQ files."
  else
    errecho -y "[${package_name}] md5sums check completed successfully"
  fi
else
  errecho -y "[${package_name}] Skipping md5sum check"
fi

## Infer column indices
let pid_col=$(get_index_of 'poseidon_IDs' "${ena_table_header[@]}")+1
let lib_name_col=$(get_index_of 'library_name' "${ena_table_header[@]}")+1
let instrument_model_col=$(get_index_of 'instrument_model' "${ena_table_header[@]}")+1
let instrument_platform_col=$(get_index_of 'instrument_platform' "${ena_table_header[@]}")+1
let fastq_col=$(get_index_of 'fastq_ftp' "${ena_table_header[@]}")+1
let lib_built_col=$(get_index_of 'library_built' "${ena_table_header[@]}")+1
let lib_udg_col=$(get_index_of 'udg' "${ena_table_header[@]}")+1

## Keep track of observed values
poseidon_ids=()
library_ids=()

## Paste together stuff to make a TSV. Header will flush older tsv if it exists.
errecho -y "[${package_name}] Creating TSV input for nf-core/eager (v2.*)."
echo -e "Sample_Name\tLibrary_ID\tLane\tColour_Chemistry\tSeqType\tOrganism\tStrandedness\tUDG_Treatment\tR1\tR2\tBAM" > ${out_file}
organism="Homo sapiens (modern human)"
while read line; do
  poseidon_id=$(echo "${line}" | awk -F "\t" -v X=${pid_col} '{print $X}')
  lib_name=$(echo "${line}" | awk -F "\t" -v X=${lib_name_col} '{print $X}')
  fastq_fn=$(echo "${line}" | awk -F "\t" -v X=${fastq_col} '{print $X}')         # | rev | cut -d "/" -f 1 | rev )
  instrument_model=$(echo "${line}" | awk -F "\t" -v X=${instrument_model_col} '{print $X}')
  instrument_platform=$(echo "${line}" | awk -F "\t" -v X=${instrument_platform_col} '{print $X}')
  colour_chemistry=$(infer_colour_chemistry "${instrument_platform}" "${instrument_model}")
  let lane=$(count_instances ${lib_name} "${library_ids[@]}")+1
  library_built_field=$(echo "${line}" | awk -F "\t" -v X=${lib_built_col} '{print $X}')
  udg_treatment_field=$(echo "${line}" | awk -F "\t" -v X=${lib_udg_col} '{print $X}')
  ## in the ssf file, these fields should correspond to single fastQ, so they should never be list values anymore.
  library_built=$(infer_library_strandedness ${library_built_field} 0)
  udg_treatment=$(infer_library_udg ${udg_treatment_field} 0)

  ## One set of sequencing data can correspond to multiple poseidon_ids
  for index in $(seq 1 1 $(number_of_entries ';' ${poseidon_id})); do
    row_pid=$(pull_by_index ';' ${poseidon_id} "${index}-1")
    row_lib_id="${row_pid}_${lib_name}" ## paste poseidon ID with Library ID to ensure unique naming of library results
    
    read -r seq_type r1 r2 < <(dummy_r1_r2_from_ena_fastq ${raw_data_dummy_path} ${row_lib_id}_L${lane} ${fastq_fn})
    echo -e "${row_pid}\t${row_lib_id}\t${lane}\t${colour_chemistry}\t${seq_type}\t${organism}\t${library_built}\t${udg_treatment}\t${r1}\t${r2}\tNA" >> ${out_file}
    
    ## Keep track of observed values
    poseidon_ids+=(${row_pid})
    library_names=(${row_lib_id})
  done

done < <(tail -n +2 ${ena_table})
errecho -y "[${package_name}] TSV creation completed"
