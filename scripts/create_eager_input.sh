#!/usr/bin/env bash
VERSION='0.0.1dev'

## Helptext function
function Helptext() {
  echo -ne "\t usage: ${0} [options] POSEIDON.yml\n\n"
  echo -ne "This script reads the information present in the ena_table of a poseidon package and creates a TSV file that can be used for processing the publicly available data with nf-core/eager.\n\n"
  echo -ne "Options:\n"
  echo -ne "-s, --skip_checksum\tSkip md5sum checking of input data.\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Source helper functions
source /mnt/archgen/poseidon/raw_sequencing_data/source_me.sh

## Parse CLI args.
TEMP=`getopt -q -o hvs --long help,version,skip_checksum -n "${0}" -- "$@"`
eval set -- "${TEMP}"

## Parameter defaults
poseidon_yml=''
skip_md5='FALSE'
root_download_dir='/mnt/archgen/poseidon/raw_sequencing_data'
root_output_dir='/mnt/archgen/poseidon/raw_sequencing_data/eager'

## Print helptext and exit when no option is provided.
if [[ "${#@}" == "1" ]]; then
  Helptext
  exit 0
fi

## Read in CLI arguments
while true ; do
  case "$1" in
    -s|--skip_checksum) skip_md5='TRUE'; shift ;;
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) poseidon_yml="${2}"; break ;;
    *) echo -e "invalid option provided.\n"; Helptext; exit 1;;
  esac
done

package_dir=$(dirname ${poseidon_yml})

## Error if input does not exist
if [[ ! -f ${poseidon_yml} ]]; then
  check_fail 1 "File not found: ${poseidon_yml}"
fi

## Read required info from yml file
errecho "Parsing package info from ${poseidon_yml}"
package_name=$(grep 'title' ${poseidon_yml} | cut -f 2 -d ":" | sed 's/ //g')
package_janno=${package_dir}/"$(grep -w 'jannoFile' ${poseidon_yml} | cut -f 2 -d ":" | sed 's/ //g')"
package_rawdata_dir="${root_download_dir}/${package_name}"
ena_table=${package_dir}/"$(grep -w 'sequencingSourceFile' ${poseidon_yml} | cut -f 2 -d ":" | sed 's/ //g')"
out_dir="${root_output_dir}/${package_name}"
out_file="${out_dir}/eager_${package_name}.tsv"

## This will all break down if the headers contain whitespace.
ena_table_header=($(head -n1 ${ena_table}))
janno_header=($(head -n1 ${package_janno}))
# echo ${janno_header}
# echo ${janno_header[@]}
## Checksums
if [[ ${skip_md5} != 'TRUE' ]]; then
  errecho "[${package_name}] Checking md5sums of downloaded files"
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
    errecho "[${package_name}] md5sums check completed successfully"
  fi
else
  errecho "[${package_name}] Skipping md5sum check"
fi

## Infer column indices
let pid_col=$(get_index_of 'Poseidon_ID' "${ena_table_header[@]}")+1
let lib_name_col=$(get_index_of 'library_name' "${ena_table_header[@]}")+1
let instrument_model_col=$(get_index_of 'instrument_model' "${ena_table_header[@]}")+1
let instrument_platform_col=$(get_index_of 'instrument_platform' "${ena_table_header[@]}")+1
let fastq_col=$(get_index_of 'fastq_ftp' "${ena_table_header[@]}")+1
let janno_pid_col=$(get_index_of 'Poseidon_ID' "${janno_header[@]}")+1
let janno_lib_built_col=$(get_index_of 'Library_Built' "${janno_header[@]}")+1
let janno_lib_udg_col=$(get_index_of 'UDG' "${janno_header[@]}")+1

## Get list of individuals in Janno that are not in the ENA table. If any are found, throw a warning that these will be ignored.
errecho "[${package_name}] Checking consistency between janno and sequencingSourceFile"
ena_table_pids=($(awk -F "\t" -v X=${pid_col} '{print $X}' ${ena_table} | sort -u))
janno_pids=($(awk -F "\t" -v X=${janno_pid_col} '{print $X}' ${package_janno} | sort -u))
ena_only_pids=( $(all_x_in_y ${#ena_table_pids[@]} ${ena_table_pids[@]} ${#janno_pids[@]} ${janno_pids[@]}) )
janno_only_pids=( $(all_x_in_y ${#janno_pids[@]} ${janno_pids[@]} ${#ena_table_pids[@]} ${ena_table_pids[@]}) )
if [[ ${#janno_only_pids[@]} != 0 ]]; then
  for ind in ${janno_only_pids[@]}; do
    errecho "[${package_name}] Poseidon_ID '${ind}' found in package janno, but not in ENA table. This individual will be skipped."
  done
fi

## Throw warning when some PIDs are only in ena table.
if [[ ${#ena_only_pids} != 0 ]]; then
  errecho "[${package_name}] Poseidon_ID(s) '${ena_only_pids[@]}' not found in janno file. Using default library attributes: double-stranded, non-UDG."
fi

## Keep track of observed values
poseidon_ids=()
library_ids=()

## Create output directory
mkdir -p ${out_dir}

## Paste together stuff to make a TSV. Header will flush older tsv if it exists.
errecho "[${package_name}] Creating TSV input for nf-core/eager."
echo -e "Sample_Name\tLibrary_ID\tLane\tColour_Chemistry\tSeqType\tOrganism\tStrandedness\tUDG_Treatment\tR1\tR2\tBAM" > ${out_file}
organism="Homo sapiens (modern human)"
while read line; do
  poseidon_id=$(echo "${line}" | awk -F "\t" -v X=${pid_col} '{print $X}')
  lib_name=$(echo "${line}" | awk -F "\t" -v X=${lib_name_col} '{print $X}')
  fastq_fn=$(echo "${line}" | awk -F "\t" -v X=${fastq_col} '{print $X}' | rev | cut -d "/" -f 1 | rev )
  instrument_model=$(echo "${line}" | awk -F "\t" -v X=${instrument_model_col} '{print $X}')
  instrument_platform=$(echo "${line}" | awk -F "\t" -v X=${instrument_platform_col} '{print $X}')
  colour_chemistry=$(infer_colour_chemistry "${instrument_platform}" "${instrument_model}")
  let lane=$(count_instances ${lib_name} "${library_ids[@]}")+1

  ## Now pull the information from the janno for that ID
    ## If the pid is not in janno, but only in the ena table, use default values
  if [[ $(get_index_of ${poseidon_id} "${ena_only_pids[@]}") != '' ]]; then
    library_built='double'
    udg_treatment='none'
  else
    library_built=$(infer_library_strandedness $(grep -w ${poseidon_id} ${package_janno} |  awk -F "\t" -v X=${janno_lib_built_col} '{print $X}') $(count_instances ${poseidon_id} "${poseidon_ids[@]}"))
    udg_treatment=$(infer_library_udg $(grep -w ${poseidon_id} ${package_janno} |  awk -F "\t" -v X=${janno_lib_udg_col} '{print $X}') $(count_instances ${poseidon_id} "${poseidon_ids[@]}"))
  fi

  read -r seq_type r1 r2 < <(r1_r2_from_ena_fastq ${package_rawdata_dir} ${fastq_fn})
  ## 
  echo -e "${poseidon_id}\t${lib_name}\t${lane}\t${colour_chemistry}\t${seq_type}\t${organism}\t${library_built}\t${udg_treatment}\t${r1}\t${r2}\tNA" >> ${out_file}

  ## Keep track of observed values
  poseidon_ids+=(${poseidon_id})
  library_names=(${lib_name})
done < <(tail -n +2 ${ena_table})
errecho "[${package_name}] TSV creation completed"
