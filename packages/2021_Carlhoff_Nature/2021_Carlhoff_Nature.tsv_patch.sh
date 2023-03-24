#!/usr/bin/env bash

## This script is applied to the eager input TSV file locally to edit the dummy
##    path to the fastQ files added by `create_eager_input.sh` to a real local
##    path provided as a positional argument. Any further local tweaks to the
##    TSV before running eager should be added below that in the form of bash
##    commands to aid in reproducibility.

## usage tsv_patch.sh <local_data_dir> <input_tsv>

local_data_dir=${1}
input_tsv=${2}
output_tsv="$(dirname ${input_tsv})/$(basename -s '.tsv' ${input_tsv}).finalised.tsv"

sed -e "s|<PATH_TO_DATA>|${local_data_dir}|g" ${input_tsv} > ${output_tsv}

## Any further commands to edit the file before finalisation should be added below as shown
# sed -ie 's/replace_this/with_this/g' ${output_tsv}