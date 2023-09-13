#!/usr/bin/env bash
VERSION='0.2.1dev'
set -o pipefail ## Pipefail, complain on new unassigned variables.
# set -x ## Debugging

## Helptext function
function Helptext() {
  echo -ne "\t usage: ${0} [options] Package_Minotaur_Directory\n\n"
  echo -ne "This script collects the genotype data and metadata from Minotaur-processing and creates/updates the requested poseidon package if needed.\n\n"
  echo -ne "Options:\n"
  echo -ne "-d, --debug\t\tActivates debug mode, and keeps temporary directories for troubleshooting.\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version\t\tPrint version and exit.\n"
}

## Source helper functions
repo_dir=$(dirname $(readlink -f ${0}))/..  ## The repository will be the original position of this script. If a user copies instead of symlink, this will fail.
source ${repo_dir}/scripts/source_me.sh     ## Source helper functions

## A function to make a genotype dataset for the output package out of an array of genotype files.
## Usage make_genotype_dataset_out_of_genotypes <format> <out_name> <tempdir> <geno_fn1> <geno_fn2> ...
##   format:    The format of the genotype files. Either 'PLINK' or 'EIGENSTRAT'.
##   out_name:  The name of the output genotype dataset.
##   tempdir:   The temporary directory to use for mixing the genotypes.
##   geno_fn*:  The genotype files to merge together.
## NOTE: This function uses the errecho() function defined in source_me.sh
function make_genotype_dataset_out_of_genotypes() {
  local format
  local tempdir
  local out_name
  local input_fns
  local input_fn
  local base_fn
  local ind_fns
  local geno_top_length
  local geno_bot_length

  format=${1}
  out_name=${2}
  tempdir=${3}
  shift 3
  input_fns=("${@}")

  ## Check that the format is valid.
  if [[ ${format} != "PLINK" && ${format} != "EIGENSTRAT" ]]; then
    errecho -r "[make_genotype_dataset_out_of_genotypes()]: Invalid format '${format}' provided."
    exit 1
  fi

  ## Ensure the provided temp dir exists
  if [[ ! -d ${tempdir} ]]; then
    errecho -r "[make_genotype_dataset_out_of_genotypes()]: Temporary directory '${tempdir}' not found."
    exit 1
  fi

  ## Check that the genotype files exist.
  for input_fn in ${input_fns[@]}; do
    if [[ ! -f ${input_fn} ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${input_fn}' not found."
      exit 1
    fi
  done

  ## Merge eigenstrat genotypes
  if [[ ${format} == "EIGENSTRAT" ]]; then
    ## Paste genos together. If only one is there, then it's simply a copy of it
    paste -d '\0' ${input_fns[@]} > ${tempdir}/${out_name}.geno

    ## Copy the snp file
    cp ${input_fns[0]%.geno}.snp ${tempdir}/${out_name}.snp

    ## And cat the ind files (this needs a bit of variable expansion to work)
    ind_fns=''
    for base_fn in ${input_fns[@]%.geno}; do
      ind_fns+="${base_fn}.ind "
    done
    ## Also add '_MNT' suffix to individual IDs. Set input and output field sep to TAB.
    cat ${ind_fns} | awk 'BEGIN {OFS=FS="\t"}; {$1=$1"_MNT"; print $0}' > ${tempdir}/${out_name}.ind

    ## Final sanity check, that the file dimensions are correct.
    if [[ $(wc -l ${tempdir}/${out_name}.geno | cut -f 1 -d ' ') != $(wc -l ${tempdir}/${out_name}.snp | cut -f 1 -d ' ') ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${out_name}.geno' has a different number of lines than the snp file."
      exit 1
    fi

    ## Check that the genotype dataset has a consistent length across first and last snp.
    geno_top_length=$(bc <<< "$(head -n1 ${tempdir}/${out_name}.geno | wc -c | cut -f 1 -d ' ') - 1")
    geno_bot_length=$(bc <<< "$(tail -n1 ${tempdir}/${out_name}.geno | wc -c | cut -f 1 -d ' ') - 1")
    if [[ ${geno_top_length} != ${geno_bot_length} ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${out_name}.geno' has inconsistent line lengths. Check the input datasets and try again."
      exit 1
    fi

    ## The number of characters (excluding the new line character) in the last row of the genotype file should match than the number of individuals.
    if [[ ${geno_bot_length} != $(wc -l ${tempdir}/${out_name}.ind | cut -f 1 -d ' ') ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${out_name}.geno' has a different number of lines than the ind file."
      exit 1
    fi
    errecho "[make_genotype_dataset_out_of_genotypes()]: Successfully created genotype dataset '${out_name}.{geno,snp,ind}'."

  ## Merge plink genotypes
  elif [[ ${format} == 'PLINK' ]]; then
    errecho -r "[make_genotype_dataset_out_of_genotypes()]: PLINK genotype merging not yet implemented."
    exit 1
  fi
}

## Helper function to pull minotaur versions from Config Profile Description and add them to a file.
## usage add_versions_file <package_eager_result_dir> <version_fn>
## Will create a file with the following information:
##   nf-core/eager version
##   Minotaur config version
##   CaptureType config version
##   Package config version
##   Minotaur-packager version
function add_versions_file() {
  local package_eager_result_dir
  local capture_type_config
  local version_fn
  local minotaur_version
  local eager_version
  local minotaur_versioning_string
  local minotaur_version
  local config_version
  local capture_type_version
  local capture_type_version_string
  local pipeline_report_fn

  ## Read in function params
  package_eager_result_dir=${1}
  version_fn=${2}

  pipeline_report_fn=${package_eager_result_dir}/pipeline_info/pipeline_report.txt ## The pipeline report file from nf-core/eager
  eager_version=$(grep "Pipeline Release:" ${pipeline_report_fn} | awk -F ":" '{print $NF}')

  ## Each attribute now comes in its own line. (0.2.0dev +)
  minotaur_version=$(grep "Minortaur.config" ${pipeline_report_fn} | awk -F ' ' '{print $NF}')
  ## TODO-dev un-hard-code 1240K config (future packages will have the keyword "CaptureType.XXXX.config")
  capture_type_version_string=$(grep "1240K.config" ${pipeline_report_fn})
  ## If the grep above returned nothing, then there is no Capture Type profile.
  if [[ -z ${capture_type_version_string} ]]; then
    capture_type_version=''
    capture_type_config=''
  else
    capture_type_version=$(echo ${capture_type_version_string} | awk -F ' ' '{print $NF}')
    capture_type_config="1240K" ## TODO-dev un-hard-code 1240K config (future packages will have the keyword "CaptureType.XXXX.config")
  fi

  config_version=$(grep "config_template_version" ${pipeline_report_fn} | awk -F ' ' '{print $NF}')
  package_config_version=$(grep "package_config_version" ${pipeline_report_fn} | awk -F ' ' '{print $NF}')

  ## Create the versions file. Flush any old file contents if the file exists.
  echo "nf-core/eager version: ${eager_version}"              >  ${version_fn}
  echo "Minotaur config version: ${minotaur_version}"         >> ${version_fn}
  if [[ ! -z ${capture_type_version_string} ]]; then
    echo "CaptureType profile: ${capture_type_config} ${capture_type_version}" >> ${version_fn}
  fi
  echo "Config template version: ${config_version}"           >> ${version_fn}
  echo "Package config version: ${package_config_version}"    >> ${version_fn}
  echo "Minotaur-packager version: ${VERSION}"                >> ${version_fn}
}

## Parse CLI args.
TEMP=`getopt -q -o dhv --long debug,help,version -n "${0}" -- "$@"`
eval set -- "${TEMP}"

## Parameter defaults
##   The package_minotaur_directory is the directory where the minotaur output is stored. 
##    It should look something like this:
##    /path/to/minotaur/outputs/2021_my_package/
##     ├── 2021_my_package.finalised.tsv  ## The finalised tsv file for processing with nf-core/eager
##     ├── data/                          ## The symlinks to the raw data used as eager input
##     ├── results/                       ## nf-core/eager results directory
##     └── work/                          ## Netxtflow work directory
package_minotaur_directory=''

## Print helptext and exit when no option is provided.
if [[ "${#@}" == "1" ]]; then
  Helptext
  exit 0
fi

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help)          Helptext; exit 0 ;;
    -v|--version)       echo ${VERSION}; exit 0;;
    -d|--debug)         errecho -y "[minotaur_packager.sh]: Debug mode activated."; debug_mode=1; shift ;;
    --)                 package_minotaur_directory="${2%/}"; break ;;
    *)                  echo -e "invalid option provided.\n"; Helptext; exit 1;;
  esac
done

## Infer other variables from the package_minotaur_directory provided.
package_name="${package_minotaur_directory##*/}"
package_oven_dir="/mnt/archgen/poseidon/minotaur/minotaur-package-oven/" ## Hard-coded path for EVA
output_package_dir="${package_oven_dir}/${package_name}" ## Hard-coded path for EVA
finalisedtsv_fn="${package_minotaur_directory}/${package_name}.finalised.tsv"
root_results_dir="${package_minotaur_directory}/results"

## Get current date for versioning
errecho -y "[minotaur_packager.sh]: version ${VERSION}"
date_stamp=$(date +'%Y-%M-%d')

## Check that the finalised tsv file exists.
if [[ ! -f ${finalisedtsv_fn} ]]; then
  errecho -r "[${package_name}]: Finalised tsv file not found in '${package_minotaur_directory}'."
  errecho -r "[${package_name}]: Please check the provided directory and try again."
  exit 1
fi

## Quick sanity check that the minotaur run has completed (i.e. genotypes are not newer than multiQC).
newest_genotype_fn=$(ls -Art -1 ${root_results_dir}/genotyping/*geno | tail -n 1) ## Reverse order and tail to avoid broken pipe errors
if [[ -z newest_genotype_fn && -f ${newest_genotype_fn} && ${root_results_dir}/multiqc/multiqc_report.html && ${newest_genotype_fn} -nt ${root_results_dir}/multiqc/multiqc_report.html ]]; then
  errecho -r "Minotaur run has not completed. Please ensure that processing has finished."
  exit 1
fi

## Create a temporary directory to mix and rename the genotype datasets in.
## 'tmp_dir' outside function, 'tempdir' in make_genotype_dataset_out_of_genotypes function
tmp_dir=$(mktemp -d ${package_oven_dir}/.tmp/MNT_${package_name}.XXXXXXXXXX)
check_fail $? "[${package_name}]: Failed to create temporary directory. Aborting.\nCheck your permissions in ${package_oven_dir}, and that directory ${package_oven_dir}/.tmp/ exists."

genotype_fns=($(ls -1 ${root_results_dir}/genotyping/*geno)) ## List of genotype files.

## Infer the SNP set from the config activated in the minotaur run from the config description.
##  TODO-dev Currently hard-coded to 1240K since all data thus far is 1240K. This should grep "CaptureType" from the pipeline report, and infer the SNP set from that.
# snp_set=$( grep 'Config Profile Description' ${root_results_dir}/pipeline_info/pipeline_report.txt | cut -f 2 -d ',' | cut -d ':' -f 1 | tr -d ' ' | cut -d '.' -f 1 )
snp_set="1240K"
errecho -y "[${package_name}]: SNP set inferred as '${snp_set}'."

## Check that the inferred snp set is supported. Should trigger if the inference somehow breaks.
supported_snpsets=($(ls -1 ${repo_dir}/conf/CaptureType_profiles/ | cut -d "." -f 1))
if [[ ! -z $(all_x_in_y 1 ${snp_set} ${#supported_snpsets[@]} ${supported_snpsets[@]}) ]]; then
  errecho -r "[${package_name}]: Inferred SNP set '${snp_set}' is not supported. SNP set inference might have gone wrong."
  exit 1
fi

## If the package exists and the genotypes are not newer than the package, then print a message and do nothing.
if [[ -d ${output_package_dir} ]] && [[ ! ${newest_genotype_fn} -nt ${output_package_dir}/${package_name}.geno ]]; then
  errecho -y "[${package_name}]: Package is up to date."
  exit 0

## If genotypes are new or the package does not exist, then create/update the package genotypes.
elif [[ ! -d ${output_package_dir} ]] || [[ ${newest_genotype_fn} -nt ${output_package_dir}/${package_name}.geno ]]; then
  errecho -y "[${package_name}]: Genotypes are new or package does not exist. Creating/Updating package genotypes."
  make_genotype_dataset_out_of_genotypes "EIGENSTRAT" "${package_name}" "${tmp_dir}" ${genotype_fns[@]}

  ## Create a new package with the given genotypes.
  trident init -p ${tmp_dir}/${package_name}.geno -o ${tmp_dir}/package/ -n ${package_name} --snpSet ${snp_set}
  check_fail $? "[${package_name}]: Failed to initialise package. Aborting."

  ## Fill in janno
  errecho -y "Populating janno file"
  ${repo_dir}/scripts/populate_janno.py -r ${package_minotaur_directory}/results/ -t ${finalisedtsv_fn} -p ${tmp_dir}/package/POSEIDON.yml

  ## Update the package yaml to account for the changes in the janno (update renamed to rectify)
  trident rectify -d ${tmp_dir}/package \
    --packageVersion Patch \
    --logText "Automatic update of janno file from Minotaur processing." \
    --checksumAll
    ## TODO Add poseidon core team, or Minotaur as contributors?

  ## Validate the resulting package
  trident validate -d ${tmp_dir}/package

    ## Only move package dir to "package oven" if validation passed
  if [[ $? == 0 ]] && [[ ${debug_mode} -ne 1 ]]; then
    errecho -y "## Moving '${package_name}' to package oven ##"
    ## Create directory for poseidon package in package oven
    ##  Only created now to not trip up the script if execution did not run through fully.
    mkdir -p $(dirname ${output_package_dir})

    ## Add Minotaur versioning file to package
    add_versions_file ${root_results_dir} ${tmp_dir}/package/versions.txt

    ## Move package contents to the oven
    mv ${tmp_dir}/package/ ${output_package_dir}

    ## Then remove remaining temp files
    errecho -y "## Removing temp directory ##"

    ## Paranoid of removing in root, so extra check for tmp_dir
    if [[ ! -z ${tmp_dir} ]]; then
      ## Playing it safe by avoiding rm -r
      rm ${tmp_dir}/*
      rmdir ${tmp_dir}
    fi
  fi

  ## Partially fill empty fields in janno.
# elif [[ 1 ]]; then
  ## TODO Add package updating once that is needed. For now assum each package will be made once and that's it.
fi