#!/usr/bin/env bash

package_name=$1
OUTDIR="/mnt/archgen/poseidon/raw_sequencing_data"
INDIR="${OUTDIR}/ena_table_packages/${package_name}"
LOGDIR="${OUTDIR}/download_logs"
SCRIPT="/home/stephan_schiffels/dev/poseidon-framework/scripts/download_ena_data.py"

mkdir -p $LOGDIR

# Test
# $SCRIPT -d $INDIR -o $OUTDIR --dry_run

# Submit

echo "qsub -V -b y -j y -o $LOGDIR/download.${package_name}.out -cwd $SCRIPT -d $INDIR -o $OUTDIR"