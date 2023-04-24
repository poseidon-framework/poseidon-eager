#!/usr/bin/env bash
set -uo pipefail

VERSION='0.1.0dev'

TEMP=`getopt -q -o hvadD --long help,version,test,array,dry_run,debug: -n 'run_eager.sh' -- "$@"`
eval set -- "$TEMP"

## DEBUG
# echo $TEMP

## Helptext function
function Helptext() {
    echo -ne "\t usage: ${0} [options]\n\n"
    echo -ne "This script will submit nf-core/eager runs to create a poseidon package from published sequencing data. Only runs that need (re)processing will be submitted.\n\n"
    echo -ne "Options:\n"
    echo -ne "-h, --help \t\tPrint this text and exit.\n"
    echo -ne "-a, --array \t\tWhen provided, the nf-core/eager jobs will be submitted as an array job, using 'submit_as_array.sh'. 10 jobs will run concurrently.\n"
    echo -ne "-d, --dry_run \t\tPrint the commands to be run, but run nothing. Array files will still be created.\n"
    echo -ne "-v, --version \t\tPrint qpWrapper version and exit.\n"
}

## Parameter defaults
array=''
temp_file=''
with_tower=''
dry_run="FALSE"
debug="FALSE"

## Read in CLI arguments
while true ; do
    case "$1" in
        -h|--help) Helptext; exit 0 ;;
        -d|--dry_run) dry_run="TRUE"; shift 1;;
        -v|--version) echo ${VERSION}; exit 0;;
        -a|--array) array="TRUE"; shift 1;;
        -D|--debug) debug="TRUE"; shift 1;;
        --) break ;;
        *) echo -e "invalid option provided.\n"; Helptext; exit 1;;
    esac
done

if [[ ${debug} == "TRUE" ]]; then
    echo -e "[run_eager.sh]: DEBUG activated. CLI argument parsing is not included in debug output."
    set -x
fi

## Hard-coded params
repo_dir='/mnt/archgen/poseidon/poseidon-eager'
nxf_path="/mnt/archgen/tools/nextflow/22.04.5.5708/" ## Use centarlly installed version
eager_version='2.4.6'
root_eager_dir="${repo_dir}/eager/"
root_package_dir="${repo_dir}/packages/"
nextflow_profiles="eva,archgen,medium_data,eva_local_paths"
tower_config="${repo_dir}/.nextflow_tower.conf" ## Optional tower.nf configuration
array_temp_fn_dir="${repo_dir}/array_tempfiles"
array_logs_dir="${repo_dir}/array_Logs"
submit_as_array_script="${repo_dir}/scripts/submit_as_array.sh"

## Flood execution. Useful for testing/fast processing of small batches.
if [[ ${array} == 'TRUE' ]]; then
    ## Create the required array dirs if not existing
    mkdir -p ${array_temp_fn_dir}

    temp_file="/mnt/archgen/poseidon/poseidon-eager/array_tempfiles/$(date +'%y%m%d_%H%M')_Minotaur_eager_queue.txt"
    ## Create new empty file with the correct naming, or flush contents of file if somehow it exists.
    echo -n '' > ${temp_file}
fi

for eager_input in ${root_eager_dir}/*/*.finalised.tsv; do
    ## Infer package name from finalised TSV name
    package_name=$(basename -s '.finalised.tsv' ${eager_input})

    ## Set paths needed for processing
    eager_work_dir="${root_eager_dir}/${package_name}/work"
    eager_output_dir="${root_eager_dir}/${package_name}/results"
    package_config="${root_package_dir}/${package_name}/${package_name}.config"

    ## Create necessary directories
    mkdir -p ${eager_work_dir} ${eager_output_dir}

    ## Load nf-tower configuration if it exists
    ## This loads variables needed for monitoring execution of jobs remotely.
    if [[ -f ${tower_config} ]]; then
        source ${tower_config}
        with_tower='-with-tower'
    fi

    ## Only try to run eager if the input is newer than the latest multiQC report, or the parameter config is newer than the latest report. 
    if [[ ${eager_input} -nt ${eager_output_dir}/multiqc/multiqc_report.html ]] || [[ ${package_config} -nt ${eager_output_dir}/multiqc/multiqc_report.html ]]; then
        ## Build nextflow command
        CMD="${nxf_path}/nextflow run nf-core/eager \
        -r ${eager_version} \
        -profile ${nextflow_profiles} \
        -c ${package_config} \
        --input ${eager_input} \
        --outdir ${eager_output_dir} \
        -w ${eager_work_dir} \
        ${with_tower} \
        -ansi-log false \
        -resume"
        
        ## Array setup
        if [[ ${array} == 'TRUE' ]]; then
            ## For array submissions, the commands to be run will be added one by one to the temp_file
            ## Then once all jobs have been added, submit that to qsub with each line being its own job.
            ## Use `continue` to avoid running eager interactivetly for arrayed jobs.
                echo "cd $(dirname ${eager_input}) ; ${CMD}" | tr -s " " >> ${temp_file}
                continue ## Skip running eager interactively if arrays are requested.
            fi
        
        ## NON-ARRAY RUNS
        ## Change to input directory to run from, to keep one cwd per run.
        cd $(dirname ${eager_input})
        
        ## Debugging info.
        echo "Running eager on ${eager_input}:"
        echo "${CMD}"
        

        ## Don't run comands if dry run specified.
        if [[ ${dry_run} == "FALSE" ]]; then
            $CMD
        fi

        cd ${root_eager_dir} ## Then back to root dir
    fi
done

## If array is requested submit the created array file to qsub below
if [[ ${array} == 'TRUE' ]]; then
    mkdir -p ${array_logs_dir}/$(basename -s '.txt' ${temp_file}) ## Create new directory for the logs for more traversable structure
    jn=$(wc -l ${temp_file} | cut -f 1 -d " ") ## number of jobs equals number of lines
    export NXF_OPTS='-Xms4G -Xmx4G' ## Set 4GB limit to Nextflow VM
    export JAVA_OPTS='-Xms8G -Xmx8G' ## Set 8GB limit to Java VM
    ## -V Pass environment to job (includes nxf/java opts)
    ## -S /bin/bash Use bash
    ## -l v_hmem=40G ## 40GB memory limit (8 for java + the rest for garbage collector)
    ## -pe smp 2 ## Use two cores. one for nextflow, one for garbage collector
    ## -n AE_spawner ## Name the job
    ## -cwd Run in currect run directory (ran commands include a cd anyway, but to find the files at least)
    ## -j y ## join stderr and stdout into one output log file
    ## -b y ## Provided command is a binary already (i.e. executable)
    ## -o /mnt/archgen/Autorun_eager/array_Logs/ ## Keep all log files in one directory.
    ## -tc 10 ## Number of concurrent spawner jobs (10)
    ## -t 1-${jn} ## The number of array jobs (from 1 to $jn)
    array_cmd="qsub \
    -V \
    -S /bin/bash \
    -l h_vmem=40G \
    -pe smp 2 \
    -N Minotaur_spawner_$(basename ${temp_file}) \
    -cwd \
    -j y \
    -b y \
    -o /mnt/archgen/Autorun_eager/array_Logs/$(basename ${temp_file}) \
    -tc 10 \
    -t 1-${jn} \
    $submit_as_array_script ${temp_file}"

    echo ${array_cmd}
    ## Don't run comands if dry run specified.
    if [[ ${dry_run} == "FALSE" ]]; then
        $array_cmd
    fi
fi
