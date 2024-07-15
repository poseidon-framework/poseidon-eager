#!/usr/bin/env bash
VERSION='0.3.0dev'
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
  local populate_janno_version

  ## Read in function params
  package_eager_result_dir=${1}
  version_fn=${2}

  pipeline_report_fn=${package_eager_result_dir}/pipeline_info/pipeline_report.txt ## The pipeline report file from nf-core/eager
  eager_version=$(grep "Pipeline Release:" ${pipeline_report_fn} | awk -F ":" '{print $NF}')

  ## Each attribute now comes in its own line. (0.2.0dev +)
  minotaur_version=$(grep "Minotaur.config" ${pipeline_report_fn} | awk -F ' ' '{print $NF}')
  capture_type_version_string=$(grep '^ - CaptureType\.[0-9A-Za-z]*\.config' ${pipeline_report_fn})
  ## If the grep above returned nothing, then there is no Capture Type profile.
  if [[ -z ${capture_type_version_string} ]]; then
    errecho -y "[${package_name}]: No CaptureType profile used for package."
    capture_type_version=''
    capture_type_config=''
  else
    capture_type_version=$(echo ${capture_type_version_string} | awk -F ' ' '{print $NF}')
    capture_type_config=$(echo ${capture_type_version_string} | awk -F '.' '{print $2}') ## If there is a capture type profile, it is the second field in the string, surrounded by '.'.
    errecho -y "[${package_name}]: Package was processed using the ${capture_type_config} CaptureType profile, with version ${capture_type_version}."
  fi

  config_version=$(grep "config_template_version" ${pipeline_report_fn} | awk -F ' ' '{print $NF}')
  package_config_version=$(grep "package_config_version" ${pipeline_report_fn} | awk -F ' ' '{print $NF}')
  populate_janno_version=$(${repo_dir}/scripts/populate_janno.py -v)

  errecho -y "[${package_name}]: Writing version info to '${version_fn}'."
  ## Create the versions file. Flush any old file contents if the file exists.
  echo "# ${package_name}"                                        > ${version_fn}
  echo "This package was created on $(date +'%Y-%m-%d') and was processed using the following versions:" >> ${version_fn}
  echo " - nf-core/eager version: ${eager_version}"               >> ${version_fn}
  echo " - Minotaur config version: ${minotaur_version}"          >> ${version_fn}
  if [[ ! -z ${capture_type_version_string} ]]; then
    echo " - CaptureType profile: ${capture_type_config}"         >> ${version_fn}
    echo " - CaptureType config version: ${capture_type_version}" >> ${version_fn}
  fi
  echo " - Config template version: ${config_version}"            >> ${version_fn}
  echo " - Package config version: ${package_config_version}"     >> ${version_fn}
  echo " - Minotaur-packager version: ${VERSION}"                 >> ${version_fn}
  echo " - populate_janno.py version: ${populate_janno_version}"  >> ${version_fn}
}

## Function to add SSF file to minotaur package
## usage add_ssf_file <ssf_file_path> <package_dir>
function add_ssf_file() {
  local ssf_file_path
  local ssf_name
  local package_dir
  local package_name

  ssf_file_path=${1}
  ssf_name=${ssf_file_path##*/}
  package_dir=${2}
  package_name=${package_dir##*/}

  ## Check that the SSF file exists.
  if [[ ! -f ${ssf_file_path} ]]; then
    errecho -r "[${package_name}]: SSF file '${ssf_file_path}' not found."
    exit 1
  fi

  ## Ensure the provided package dir exists
  if [[ ! -d ${package_dir} ]]; then
    errecho -r "[${package_name}]: Package directory '${package_dir}' not found."
    exit 1
  fi

  ## Copy the SSF file to the package directory
  errecho -y "[${package_name}]: Adding SSF file to package directory."
  # cp ${ssf_file_path} ${package_dir}/${ssf_name}
  awk 'BEGIN{FS=OFS="\t"} NR==1 { # Process header
        for (i=1; i<=NF; i++) {
            if ($i == "poseidon_IDs") {  # Use "poseidon_IDs" as the column name
                poseidon_col_index = i;
            }
            if ($i == "library_built") {  # Use "library_built" as the column name
                library_col_index = i;
            }
        }
        print $0; # Print header
    }
    NR>1 {  # Process data rows
        if (poseidon_col_index > 0 && library_col_index > 0) {
            if ($library_col_index == "ss") {
                gsub(/;/,"_MNT;",$poseidon_col_index);
                $poseidon_col_index = $poseidon_col_index "_ss_MNT";
            } else {
                gsub(/;/,"_MNT;",$poseidon_col_index);
                $poseidon_col_index = $poseidon_col_index "_MNT";
            }
        }
        print $0;
    }' ${ssf_file_path} > ${package_dir}/${ssf_name}
}

function sort_and_bake_poseidon_package() {
  local origin_pkg_dir
  local output_pkg_dir
  local package_name

  origin_pkg_dir=${1}
  output_pkg_dir=${2}
  package_name=${output_pkg_dir##*/}

  ## Check that the origin package directory exists and contains a POSEIDON.yml.
  if [[ ! -d ${origin_pkg_dir} ]]; then
    errecho -r "[${package_name}]: Origin package directory '${origin_pkg_dir}' not found."
    exit 1
  elif [[ ! -f ${origin_pkg_dir}/POSEIDON.yml ]]; then
    errecho -r "[${package_name}]: Origin package directory '${origin_pkg_dir}' does not contain a POSEIDON.yml file."
    exit 1
  fi

  ## Create output directory if necessary
  mkdir -p ${output_pkg_dir}

  ## Use qjanno to create the desired sorted order of Poseidon_IDs
  errecho -y "[${package_name}]: Creating desired order file."
  qjanno "SELECT '<'||Poseidon_ID||'>' FROM d(${origin_pkg_dir}) ORDER BY Poseidon_ID" --raw --noOutHeader > desiredOrder.txt
  check_fail $? "[${package_name}]: Failed to create desired order file. Aborting."

  ## Sort the package dough and put resulting package in the output directory
  errecho -y "[${package_name}]: Sorting package dough and moving to package oven"
  trident forge -d ${origin_pkg_dir} \
    --forgeFile desiredOrder.txt \
    -o ${output_pkg_dir} \
    --ordered \
    --preservePyml
  check_fail $? "[${package_name}]: Failed to sort package dough. Aborting."

  ## Rectify the sorted package
  errecho -y "[${package_name}]: Rectifying package"
  trident rectify -d ${output_pkg_dir} \
    --packageVersion Minor \
    --logText "Rearrange Poseidon_IDs alphabetically." \
    --checksumAll
  check_fail $? "[${package_name}]: Failed to rectify package. Aborting."

  ## Validate the sorted package
  errecho -y "[${package_name}]: Validating package"
  trident validate -d ${output_pkg_dir}
  check_fail $? "[${package_name}]: Failed to validate sorted package. Aborting."
}

## Parse CLI args.
TEMP=`getopt -q -o dhfv --long debug,help,force,version -n "${0}" -- "$@"`
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
force_recreate="FALSE"
debug_mode=0

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
    -f|--force)         force_recreate="TRUE"; errecho -r "[minotaur_packager.sh]: Forcing package recreation."; shift ;;
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
minotaur_recipe_dir="/mnt/archgen/poseidon/minotaur/minotaur-recipes/packages/${package_name}" ## Hard-coded path for EVA

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
if [[ -d ${output_package_dir} ]] && [[ ! ${newest_genotype_fn} -nt ${output_package_dir}/${package_name}.bed ]] && [[ ${force_recreate} != "TRUE" ]]; then
  errecho -y "[${package_name}]: Package is up to date."
  exit 0

## If the package does not exist, then create the package genotypes.
## TODO-dev Once we go live this should be updated to apply to new packages only, and the updating should be moved to its own block.
elif [[ ! -d ${output_package_dir} ]] || [[ ${newest_genotype_fn} -nt ${output_package_dir}/${package_name}.bed ]] || [[ ${force_recreate} == "TRUE" ]]; then
  errecho -y "[${package_name}]: Genotypes are new or package does not exist. Creating/Updating package genotypes."
  make_genotype_dataset_out_of_genotypes "EIGENSTRAT" "${package_name}" "${tmp_dir}" ${genotype_fns[@]}

  ## Create a new package with the given genotypes.
  trident init -p ${tmp_dir}/${package_name}.geno -o ${tmp_dir}/package/ -n ${package_name} --snpSet ${snp_set}
  check_fail $? "[${package_name}]: Failed to initialise package. Aborting."

  ## Add self as contributor to poseidon package
  ##  Trident 1.5.* does not include Josiah Carberry anymore, which breaks pyJanno if the field is empty.
  trident rectify --packageVersion Patch \
    -d ${tmp_dir}/package \
    --newContributors '[Thiseas C. Lamnidis](thiseas_christos_lamnidis@eva.mpg.de)' \
    --logText "Added self as contributor to package."
  check_fail $? "[${package_name}]: Failed to add contributor. Aborting."

  ## Fill in janno
  errecho -y "[${package_name}]: Populating janno file"
  ${repo_dir}/scripts/populate_janno.py -r ${package_minotaur_directory}/results/ -t ${finalisedtsv_fn} -p ${tmp_dir}/package/POSEIDON.yml -s ${minotaur_recipe_dir}/${package_name}.ssf
  check_fail $? "[${package_name}]: Failed to populate janno. Aborting."

  ## TODO-dev Infer genetic sex from janno and mirror to ind file.

  ## Add Minotaur version info to README of package
  add_versions_file ${root_results_dir} ${tmp_dir}/package/README.md
  echo "readmeFile: README.md" >> ${tmp_dir}/package/POSEIDON.yml

  ## Add SSF file to package
  add_ssf_file ${minotaur_recipe_dir}/${package_name}.ssf ${tmp_dir}/package
  echo "sequencingSourceFile: ${package_name}.ssf" >> ${tmp_dir}/package/POSEIDON.yml

  ## Convert data to PLINK format
  errecho -y "[${package_name}] Converting data to PLINK format"
  trident genoconvert \
    -d ${tmp_dir}/package \
    --outFormat PLINK \
    --removeOld
  check_fail $? "[${package_name}]: Failed to convert data to PLINK format. Aborting."

  ## Update the package yaml to account for the changes in the janno (update renamed to rectify)
  errecho -y "[${package_name}] Rectifying package"
  trident rectify -d ${tmp_dir}/package \
    --packageVersion Patch \
    --logText "Automatic update of janno file from Minotaur processing." \
    --checksumAll
  check_fail $? "[${package_name}]: Failed to rectify package after janno update. Aborting."

  ## Validate the resulting package
  errecho -y "[${package_name}] Validating package"
  trident validate -d ${tmp_dir}/package
  check_fail $? "[${package_name}]: Failed to validate package. Aborting."

    ## Only move package dir to "package oven" if validation passed
  if [[ $? == 0 ]] && [[ ${debug_mode} -ne 1 ]]; then
    ## Create directory for poseidon package in package oven
    ##  Only created now to not trip up the script if execution did not run through fully.
    mkdir -p $(dirname ${output_package_dir})

    ## If the package directory already exists, remove it
    if [[ -d ${output_package_dir} ]]; then
      errecho -y "[${package_name}] Removing old package directory"
      rm -r ${output_package_dir}
    fi

    ## Create a sorted copy of the package in the oven
    errecho -y "[${package_name}] Sorting package dough and moving to package oven"
    sort_and_bake_poseidon_package ${tmp_dir}/package ${output_package_dir}
    check_fail $? "[${package_name}]: Failed to sort package dough. Aborting."

    ## Then remove remaining temp files
    errecho -y "[${package_name}] Removing temp directory"

    ## Paranoid of removing in root, so extra check for tmp_dir
    if [[ ! -z ${tmp_dir} ]]; then
      ## Playing it safe by avoiding rm -r
      rm ${tmp_dir}/package/*
      rmdir ${tmp_dir}/package
      rm ${tmp_dir}/*
      rmdir ${tmp_dir}
    fi
  fi

  ## Partially fill empty fields in janno.
# elif [[ 1 ]]; then
  ## If genotypes are new and the package exists, then update the package.
  ## TODO Add package updating once that is needed. For now assume each package will be made once and that's it.
fi
