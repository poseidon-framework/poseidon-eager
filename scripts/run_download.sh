#!/usr/bin/env bash

## This script submits an SGE job that sequentially downloads all the ENA FastQ files
##    found in poseidon-formatted sequencingSourceFiles.
##    !! This is a localised script, including hard-coded paths for processing in MPI-EVA. !!
package_name=$1
OUTDIR="/mnt/archgen/poseidon/raw_sequencing_data"
INDIR="/mnt/archgen/poseidon/poseidon-eager/packages/${package_name}"
LOGDIR="${OUTDIR}/download_logs"
SCRIPT="/mnt/archgen/poseidon/poseidon-eager/scripts/download_ena_data.py"

mkdir -p $LOGDIR

# Test
# $SCRIPT -d $INDIR -o $OUTDIR --dry_run

# Submit

qsub -V -b y -j y -N "ENA_DL_${package_name}" -o $LOGDIR/download.${package_name}.out -cwd $SCRIPT -d $INDIR -o $OUTDIR 