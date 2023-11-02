#!/usr/bin/env bash
set -o pipefail ## Pipefail, complain on new unassigned variables.

VERSION='0.2.1dev'

## Helptext function
function Helptext() {
  echo -ne "\t usage: ${0} [options] package_name\n\n"
  echo -ne "This script takes in the name of a package as it appears in './packages', and carries out the localisation operation necessary to prepare for nf-core/eager processing.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Parse CLI args.
TEMP=`getopt -q -o hv --long help,version -n "${0}" -- "$@"`
eval set -- "${TEMP}"

##Parameter defaults
package_name=''
script_debug_string="[localise_package_files.sh]:"

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help)          Helptext; exit 0 ;;
    -v|--version)       echo ${VERSION}; exit 0;;
    --)                 package_name="${2}"; break ;;
    *)                  echo -e "invalid option provided.\n"; Helptext; exit 1;;
  esac
done

## Source helper functions
repo_dir=$(dirname $(readlink -f ${0}))/..  ## The repository will be the original position of this script. If a user copies instead of symlink, this will fail.
source ${repo_dir}/scripts/source_me.sh     ## Source helper functions

if [[ -z package_name ]]; then
  errecho -r "${script_debug_string} No package name provided."
  Helptext
  exit 1
fi

## Other variables inferred from repo dir and pacakge name.
package_dir="${repo_dir}/packages/${package_name}/"
ssf_file="${package_dir}/${package_name}.ssf"
download_dir="${repo_dir}/raw_sequencing_data/"
download_log_dir="${download_dir}/download_logs"
local_data_dir="${repo_dir}/raw_sequencing_data/${package_name}"
package_eager_dir="${repo_dir}/eager/${package_name}/"
symlink_dir="${package_eager_dir}/data"
tsv_patch_fn="${package_dir}/${package_name}.tsv_patch.sh"
original_tsv="${package_dir}/${package_name}.tsv"

## STEP 1: Download data
##   Add a header to the log to keep track of when each part was ran and what version was used.
echo "[download_ena_data.py]: $(date +'%y%m%d_%H%M') ${package_name}" >> ${download_log_dir}/download.${package_name}.out
echo "[download_ena_data.py]: version $(${repo_dir}/scripts/download_ena_data.py --version)" >> ${download_log_dir}/download.${package_name}.out
${repo_dir}/scripts/download_ena_data.py -d ${package_dir} -o ${download_dir} 2>> ${download_log_dir}/download.${package_name}.out
check_fail $? "${script_debug_string} Downloads did not finish completely. Try again."

## STEP 2: Validate downloaded files.
mkdir -p ${symlink_dir}
${repo_dir}/scripts/validate_downloaded_data.sh ${ssf_file} ${local_data_dir} ${package_eager_dir}
check_fail $? "${script_debug_string} Validation and symlink creation failed."

## STEP 3: Localise TSV file.
errecho -y "${script_debug_string} Localising TSV for nf-core/eager."
${tsv_patch_fn} ${symlink_dir} ${original_tsv}
check_fail $? "${script_debug_string} TSV localisation failed."
