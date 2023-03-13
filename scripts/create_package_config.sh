#!/usr/bin/env bash
set -uo pipefail

## Load helper bash functions
source $(dirname ${0})/source_me.sh

package_name=$1
outdir="/mnt/archgen/poseidon/poseidon-eager/packages/${package_name}"
package_conf="${outdir}/${package_name}.config"
config_template="$(dirname ${0})/../assets/template.config"

[[ -d ${outdir} ]] ; check_fail $? "[${package_name}]: Package directory does not exist"

cp ${config_template} ${package_conf}