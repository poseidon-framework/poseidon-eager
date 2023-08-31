#!/usr/bin/env python3

import pyEager
import argparse
import os
import glob
import pandas as pd
import yaml
from collections import namedtuple

VERSION = "0.2.0dev"


def camel_to_snake(name):
    name = re.sub("(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub("([a-z0-9])([A-Z])", r"\1_\2", name).lower()


## Function that takes a pd.DataFrame and the name of a column, and applies the format to it to add a new column named poseidon_id
class PoseidonYaml:
    def __init__(self, path_poseidon_yml):
        ## Check that path_poseidon_yml exists. Throw error if not.
        if not os.path.exists(path_poseidon_yml):
            raise ValueError(
                "The path to the poseidon yml file does not exist. Provided path '{}'.".format(
                    path_poseidon_yml
                )
            )
        ## Read in yaml file and set attributes.
        self.yaml_data = yaml.safe_load(open(path_poseidon_yml))
        self.package_dir = os.path.dirname(path_poseidon_yml)
        self.poseidon_version = self.yaml_data["poseidonVersion"]
        self.title = self.yaml_data["title"]
        self.description = self.yaml_data["description"]
        self.contributor = self.yaml_data["contributor"]
        self.package_version = self.yaml_data["packageVersion"]
        self.last_modified = self.yaml_data["lastModified"]
        self.janno_file = os.path.join(self.package_dir, self.yaml_data["jannoFile"])
        self.janno_file_chk_sum = self.yaml_data["jannoFileChkSum"]
        self.sequencing_source_file = os.path.join(
            self.package_dir, self.yaml_data["sequencingSourceFile"]
        )
        self.sequencing_source_file_chk_sum = self.yaml_data[
            "sequencingSourceFileChkSum"
        ]
        self.bib_file = os.path.join(self.package_dir, self.yaml_data["bibFile"])
        self.bib_file_chk_sum = self.yaml_data["bibFileChkSum"]
        self.changelog_file = os.path.join(
            self.package_dir, self.yaml_data["changelogFile"]
        )
        ## For each key-value pair in dict, check if key is genoFile. If so, join the package_dir to the value. Else, just add the value.
        ## Also convert keys from camelCase to snake_case.
        genotype_data = {}
        for key, value in self.yaml_data["genotypeData"].items():
            if key.endswith("File"):
                genotype_data[camel_to_snake(key)] = os.path.join(
                    self.package_dir, value
                )
            else:
                genotype_data[camel_to_snake(key)] = value
        ## Genotype data is a dictionary in itself
        GenotypeDict = namedtuple("GenotypeDict", " ".join(genotype_data.keys()))
        self.genotype_data = GenotypeDict(**genotype_data)


parser = argparse.ArgumentParser(
    prog="populate_janno",
    description="This script reads in different nf-core/eager result files and"
    "uses this information to populate the relevant fields in a"
    "poseidon janno file. The janno file and .ind/.fam file of the"
    "package are updated, unless the --safe option is provided, in"
    "which case the output files get the suffix '.new'.",
)

parser.add_argument(
    "-r",
    "--eager_result_dir",
    metavar="<DIR>",
    required=True,
    help="The nf-core/eager result directory for the minotaur package.",
)
parser.add_argument(
    "-t",
    "--eager_tsv_path",
    metavar="<TSV>",
    required=True,
    help="The path to the eager input TSV used to generate the nf-core/eager results.",
)
parser.add_argument(
    "-p",
    "--poseidon_yml_path",
    metavar="<YML>",
    required=True,
    help="The poseidon yml file for the package.",
)
parser.add_argument(
    "--safe",
    metavar="<DIR>",
    action="store_true",
    help="Activate safe mode. The package's janno and ind files will not be updated, but instead new files will be created with the '.new' suffix. Only useful for testing.",
)
parser.add_argument("-v", "--version", action="version", version=VERSION)

args = parser.parse_args()

## Collect paths for analyses with multiple jsons.
damageprofiler_json_paths = glob.glob(
    os.path.join(args.eager_result_dir, "damageprofiler", "*", "*.json")
)
endorspy_json_paths = glob.glob(
    os.path.join(args.eager_result_dir, "endorspy", "*.json")
)
snp_coverage_json_paths = glob.glob(
    os.path.join(args.eager_result_dir, "genotyping", "*.json")
)

## Collect paths for analyses with single json.
sexdeterrmine_json_path = os.path.join(
    args.eager_result_dir, "sex_determination", "sexdeterrmine.json"
)
nuclear_contamination_json_path = os.path.join(
    args.eager_result_dir, "nuclear_contamination", "nuclear_contamination_mqc.json"
)

## Read in all JSONs into pandas DataFrames.
damage_table = pyEager.wrappers.compile_damage_table(damageprofiler_json_paths)
endogenous_table = pyEager.wrappers.compile_endogenous_table(endorspy_json_paths)
snp_coverage_table = pyEager.wrappers.compile_snp_coverage_table(
    snp_coverage_json_paths
)
contamination_table = pyEager.parsers.parse_nuclear_contamination_json(
    nuclear_contamination_json_path
)
sex_determination_table = pyEager.parsers.parse_sexdeterrmine_json(
    sexdeterrmine_json_path
)
tsv_table = pyEager.parsers.parse_eager_tsv(args.eager_tsv_path)

## Read poseidon yaml, infer path to janno file and read janno file.
poseidon_yaml_data = PoseidonYaml(args.poseidon_yml_path)
janno_table = pd.read_table(poseidon_yaml_data.janno_file)

## TODO Compile all tables appropriately to populate janno file.
