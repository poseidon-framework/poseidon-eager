#!/usr/bin/env bash
set -euo pipefail

## Load helper bash functions
source $(dirname ${0})/source_me.sh

package_name=$1
outdir="/mnt/archgen/poseidon/poseidon-eager/packages/${package_name}"
mkdir -p ${outdir}

errecho -y "[${package_name}] Fetching skeleton for package"
## Get ssf file for requested package
wget https://raw.githubusercontent.com/poseidon-framework/published_data/92cb17808cd76152adbba9d7f4d44ca6eaaabf6e//${package_name}/ENAtable.tsv -O ${outdir}/ENAtable.tsv.partial
if [[ $? == 0 ]]; then mv ${outdir}/ENAtable.tsv.partial ${outdir}/ENAtable.tsv; errecho -y "[${package_name}] ENA table downloaded successfully"; else exit 1; fi

## Remove quotes from ENAtable.tsv
errecho -y "[${package_name}] Removing quotes from ENA table"
sed -i 's/"//g' ${outdir}/ENAtable.tsv

## Rename ssf file to proper naming
## TODO in future, this will hopefully be the actual names/the package name will be DEFINED by the ssf.
mv ${outdir}/ENAtable.tsv ${outdir}/${package_name}.ssf

errecho -y "[${package_name}] Achievement unlocked: Package skeleton get!"
