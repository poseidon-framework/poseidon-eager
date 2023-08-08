#!/usr/bin/env python3

import pyEager
import argparse
import os
import glob
import pandas as pd

VERSION = "0.2.0dev"

parser = argparse.ArgumentParser(
    prog = 'populate_janno',
    description = 'This script reads in different nf-core/eager result files and'
                    'uses this information to populate the relevant fields in a'
                    'poseidon janno file. The janno file and .ind/.fam file of the'
                    'package are updated, unless the --safe option is provided, in'
                    'which case the output files get the suffix \'.new\'.'
    )

parser.add_argument('-r', '--eager_result_dir', metavar="<DIR>", required=True, help="The nf-core/eager result directory for the minotaur package.")
parser.add_argument('-t', '--eager_tsv_path', metavar="<TSV>", required=True, help="The path to the eager input TSV used to generate the nf-core/eager results.")
parser.add_argument('-p', '--poseidon_yml_path', metavar="<YML>", required=True, help="The poseidon yml file for the package.")
parser.add_argument('--safe', metavar="<DIR>", action='store_true', help="Activate safe mode. The package's janno and ind files will not be updated, but instead new files will be created with the '.new' suffix. Only useful for testing.")
parser.add_argument('-v', '--version', action='version', version=VERSION)

args = parser.parse_args()

damageprofiler_json_paths=glob.glob(os.path.join(args.eager_result_dir, "damageprofiler", "*", "*.json"))
endorspy_json_paths=glob.glob(os.path.join(args.eager_result_dir, "endorspy", "*.json"))
snp_coverage_json_paths=glob.glob(os.path.join(args.eager_result_dir, "genotyping", "*.json"))
nuclear_contamination_json_path=os.path.join(args.eager_result_dir, "nuclear_contamination", "nuclear_contamination_mqc.json")

damage_table=pyEager.wrappers.compile_damage_table(damageprofiler_json_paths)
endogenous_table=pyEager.wrappers.compile_endogenous_table(endorspy_json_paths)
snp_coverage_table=pyEager.wrappers.compile_snp_coverage_table(snp_coverage_json_paths)
contamination_table=pyEager.parsers.parse_nuclear_contamination_json(nuclear_contamination_json_path)

## TODO check tables above.