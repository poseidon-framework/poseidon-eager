#!/usr/bin/env python3

import pyEager
import argparse
import os
import glob
import pandas as pd
import yaml
import re
import numpy as np
from collections import namedtuple

VERSION = "0.5.0"


def get_eager_version(eager_result_dir):
    software_versions_csv_fn = os.path.join(
        eager_result_dir, "pipeline_info", "software_versions.csv"
    )
    ## Check the file xists, and if so, read it in and return the version of nf-core/eager
    if os.path.exists(software_versions_csv_fn):
        with open(software_versions_csv_fn, "r") as f:
            for line in f:
                if line.strip().split()[0] == "nf-core/eager":
                    return line.strip().split()[1].lstrip("v")
    else:
        return None


def camel_to_snake(name):
    name = re.sub("(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub("([a-z0-9])([A-Z])", r"\1_\2", name).lower()


def infer_library_name(row, prefix_col=None, target_col=None):
    strip_me = "{}_".format(row[prefix_col])
    from_me = row[target_col]

    ## First, remove the added prefix
    if from_me.startswith(strip_me):
        inferred_name = from_me.replace(strip_me, "", 1)
    else:
        inferred_name = from_me

    ## Finally, strip the hard-coded suffix if there.
    if inferred_name.endswith("_ss"):
        inferred_name = inferred_name.replace("_ss", "", 1)
    else:
        inferred_name = inferred_name

    return inferred_name


def set_contamination_measure(row):
    ## If the row's contamination is not NaN, then set to "ANGSD", otherwise NaN
    if not pd.isna(row["Contamination"]):
        return "ANGSD[v0.935]"  ## TODO-dev infer the version from eager software_versions.txt
    else:
        return np.nan


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
        ## Optional attributes
        for attribute in [
            "janno_file_chk_sum",
            "sequencing_source_file",
            "sequencing_source_file_chk_sum",
            "bib_file",
            "bib_file_chk_sum",
            "changelog_file",
        ]:
            try:
                if attribute.endswith("File"):
                    setattr(
                        self,
                        attribute,
                        os.path.join(self.package_dir, self.yaml_data[attribute]),
                    )
                else:
                    setattr(self, attribute, self.yaml_data[attribute])
            except:
                setattr(self, attribute, None)


## Function to calculate weighted mean of a group from the weight and value columns specified.
def weighted_mean(
    group, wt_col="wt", val_col="val", filter_col="filter_col", min_val=100
):
    non_nan_indices = ~group[val_col].isna()
    filter_indices = group[filter_col] >= min_val  ## Remove values below the cutoff
    valid_indices = non_nan_indices & filter_indices
    if valid_indices.any():
        weighted_values = (
            group.loc[valid_indices, wt_col] * group.loc[valid_indices, val_col]
        )
        total_weight = group.loc[
            valid_indices, wt_col
        ].sum()  # Calculate total weight without excluded weights
        weighted_mean = weighted_values.sum() / total_weight
    else:
        weighted_mean = np.nan  # Return NaN if no valid values left
    return weighted_mean


## Function to convert library strategy to poseidon CaptureType
def library_strategy_to_capture_type(df, strategy_col, snp_set):
    if df[strategy_col] == "WGS":
        return "Shotgun"
    elif df[strategy_col] == "Targeted-Capture":
        return snp_set
    elif df[strategy_col] == "OTHER":
        return "OtherCapture"
    else:
        return "n/a"


## Function to convert UDG_Treatment to poseidon UDG
def udg_treatment_to_udg(df):
    if df["UDG_Treatment"] == "none":
        df["UDG_Treatment"] = "minus"
    elif df["UDG_Treatment"] == "half":
        df["UDG_Treatment"] = "half"
    elif df["UDG_Treatment"] == "full":
        df["UDG_Treatment"] = "plus"
    elif df["UDG_Treatment"] == "mixed":
        df["UDG_Treatment"] = "mixed"
    else:
        df["UDG_Treatment"] = "n/a"
    return df


## Function to add suffix to column X when column y is equal to target.
def add_suffix_if(df, x, y, if_y, suffix="_ss"):
    if df[y] == if_y:
        df[x] = df[x] + suffix
    return df


## Function to convert poseidon_ID and Library_ID to minotaur_library_ID
def infer_minotaur_library_id(df):
    ## remove _MNT suffix, then add _ss if the library_built column is ss.
    df["new_poseidon_IDs"] = df.poseidon_IDs.str.removesuffix("_MNT")
    df["new_library_name"] = df.library_name
    df = df.apply(
        add_suffix_if, axis=1, args=("new_poseidon_IDs", "library_built", "ss", "_ss")
    )
    df = df.apply(
        add_suffix_if, axis=1, args=("new_library_name", "library_built", "ss", "_ss")
    )
    df["minotaur_library_ID"] = df.new_poseidon_IDs + "_" + df.new_library_name
    return df


## Argument parsing
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
    action="store_true",
    help="Activate safe mode. The package's janno and ind files will not be updated, but instead new files will be created with the '.new' suffix. Only useful for testing.",
)
parser.add_argument(
    "-s",
    "--ssf_path",
    metavar="<SSF>",
    required=True,
    help="The path to the SSF file of the recipe for the minotaur package.",
)
parser.add_argument("-v", "--version", action="version", version=VERSION)

args = parser.parse_args()

## Collect paths for analyses with multiple jsons.
damage_estimation_paths = glob.glob(
    os.path.join(args.eager_result_dir, "damageprofiler", "*", "*.json")
) + glob.glob(os.path.join(args.eager_result_dir, "mapdamage", "*"))
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
damage_table = pyEager.wrappers.compile_damage_table(damage_estimation_paths)
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
tsv_table = pyEager.parsers.infer_merged_bam_names(
    tsv_table, run_trim_bam=True, skip_deduplication=False
)

ssf_table = pd.read_table(args.ssf_path, dtype=str)

## Read poseidon yaml, infer path to janno file and read janno file.
poseidon_yaml_data = PoseidonYaml(args.poseidon_yml_path)
janno_table = pd.read_table(poseidon_yaml_data.janno_file, dtype=str)
## Add Main_ID to janno table. That is the Poseidon_ID after removing minotaur processing related suffixes.
janno_table["Eager_ID"] = janno_table["Poseidon_ID"].str.replace(r"_MNT", "")
janno_table["Main_ID"] = janno_table["Eager_ID"].str.replace(r"_ss", "")

## Prepare damage table for joining. Infer eager Library_ID from id column, by removing '_rmdup.bam' suffix
## The "_rmdup" is removed separately to also apply to mapdamage results (which lack the .bam suffix)
## TODO-dev Check if this is the correct way to infer Library_ID from id column when the results are on the sample level.
damage_table["Library_ID"] = (
    damage_table["id"].str.replace(r"_rmdup", "").str.replace(r".bam", "")
)
damage_table = damage_table[["Library_ID", "n_reads", "dmg_5p_1bp"]].rename(
    columns={"dmg_5p_1bp": "damage"}
)

## Prepare endogenous table for joining. Should be max value in cases where multiple libraries are merged. But also, should be SG data ONLY, which is unlikely to work well with ENA datasets where TF and SG reads might be merged.
endogenous_table = endogenous_table[["id", "endogenous_dna"]].rename(
    columns={"id": "Library_ID", "endogenous_dna": "endogenous"}
)
## Get df with minotaur_library_ids that are WGS. Used to decide on which libraries to keep the endogenous results for.
##  the strandedness of the library is also used to infer the minotaur_library_id.
library_strategy_table = ssf_table[
    ["poseidon_IDs", "library_name", "library_strategy", "library_built"]
].drop_duplicates()
library_strategy_table = library_strategy_table[
    library_strategy_table.library_strategy == "WGS"
]
library_strategy_table["poseidon_IDs"] = library_strategy_table.poseidon_IDs.apply(
    lambda x: x.split(";")
)
library_strategy_table = library_strategy_table.explode("poseidon_IDs")
library_strategy_table = infer_minotaur_library_id(library_strategy_table).apply(
    add_suffix_if, axis=1, args=("poseidon_IDs", "library_built", "ss")
)
library_strategy_table = library_strategy_table[
    ["minotaur_library_ID", "library_strategy"]
]

## Merge the two tables, only keeping endogenous values for WGS libraries.
endogenous_table = endogenous_table.merge(
    library_strategy_table,
    left_on="Library_ID",
    right_on="minotaur_library_ID",
    how="right",
).drop(columns=["minotaur_library_ID", "library_strategy"])

## Prepare table with Library_Built column. Infer from the SSF table.
library_built_table = ssf_table[
    ["poseidon_IDs", "library_built", "library_strategy"]
].drop_duplicates()
library_built_table["poseidon_IDs"] = library_built_table.poseidon_IDs.apply(
    lambda x: x.split(";")
)
library_built_table = library_built_table.explode("poseidon_IDs")
library_built_table["poseidon_IDs"] = library_built_table.poseidon_IDs.str.removesuffix(
    "_MNT"
)
library_built_table = library_built_table.apply(
    add_suffix_if,
    axis=1,
    args=("poseidon_IDs", "library_built", "ss", "_ss"),
)

library_built_table["library_strategy"] = library_built_table.apply(
    library_strategy_to_capture_type,
    args=("library_strategy", poseidon_yaml_data.genotype_data.snp_set),
    axis=1,
)


## Prepare Genetic_Source Accession IDs. Infer from SSF table.
def unique_values_join(x, sep=";"):
    return sep.join(x.unique())


accession_table = ssf_table[
    [
        "poseidon_IDs",
        "study_accession",
        "run_accession",
        "secondary_sample_accession",
        "library_built",
    ]
].drop_duplicates()
accession_table["poseidon_IDs"] = accession_table.poseidon_IDs.apply(
    lambda x: x.split(";")
)
accession_table = accession_table.explode("poseidon_IDs")
accession_table["poseidon_IDs"] = accession_table.poseidon_IDs.str.removesuffix("_MNT")
accession_table = accession_table.apply(
    add_suffix_if, axis=1, args=("poseidon_IDs", "library_built", "ss", "_ss")
)
accession_table = accession_table.groupby("poseidon_IDs").agg(
    {
        "study_accession": unique_values_join,
        "run_accession": unique_values_join,
        "secondary_sample_accession": unique_values_join,
    }
)
column_order = ["study_accession", "secondary_sample_accession", "run_accession"]
accession_table["Genetic_Source_Accession_IDs"] = accession_table.apply(
    lambda row: ";".join(row[column_order]), axis=1
)
accession_table = accession_table.drop(
    [
        "study_accession",
        "secondary_sample_accession",
        "run_accession",
    ],
    axis=1,
).reset_index()

## Prepare SNP coverage table for joining. Should always be on the sample level, so only need to fix column names.
snp_coverage_table = snp_coverage_table.drop("Total_Snps", axis=1).rename(
    columns={"id": "Sample_ID", "Covered_Snps": "Nr_SNPs"}
)

## Prepare contamination table for joining. Always at library level. Only need to fix column names here.
contamination_table = contamination_table[
    ["id", "Num_SNPs", "Method1_ML_estimate", "Method1_ML_SE"]
].rename(
    columns={
        "id": "Library_ID",
        "Num_SNPs": "Contamination_Nr_SNPs",
        "Method1_ML_estimate": "Contamination_Est",
        "Method1_ML_SE": "Contamination_SE",
    }
)
contamination_table["Contamination_Est"] = pd.to_numeric(
    contamination_table["Contamination_Est"], errors="coerce"
)
contamination_table["Contamination_SE"] = pd.to_numeric(
    contamination_table["Contamination_SE"], errors="coerce"
)

## Prepare sex determination table for joining. Naming is sometimes at library and sometimes at sample-level, but results are always at sample level.
sex_determination_table = sex_determination_table[
    ["id", "RateX", "RateY", "RateErrX", "RateErrY"]
]

## Merge all eager tables together (plus SSF table summarised attribute: Genetic_Source_Accession_IDs)
compound_eager_table = (
    pd.DataFrame.merge(
        tsv_table,
        snp_coverage_table,
        left_on="Sample_Name",
        right_on="Sample_ID",
        validate="many_to_one",
    )
    .merge(
        ## Add contamination results per Library_ID
        contamination_table,
        on="Library_ID",
        validate="many_to_one",
    )
    .merge(
        ## Add 5p1 damage results per Library_ID
        damage_table,
        on="Library_ID",
        validate="many_to_one",
    )
    .merge(
        ## Add endogenous DNA results per Library_ID
        endogenous_table,
        on="Library_ID",
        validate="many_to_one",
        how="left",
    )
    .merge(
        ## Add sex determination results per Sample_ID
        sex_determination_table,
        left_on="sexdet_bam_name",
        right_on="id",
        validate="many_to_one",
    )
    .merge(
        ## Add Genetic_Source_Accession_IDs summarised column
        accession_table,
        left_on="Sample_Name",
        right_on="poseidon_IDs",
        validate="many_to_one",
    )
    .drop(
        ## Drop columns that are not relevant anymore
        [
            "Lane",
            "Colour_Chemistry",
            "SeqType",
            "Organism",
            "Strandedness",
            "R1",
            "R2",
            "BAM",
            "initial_merge",
            "additional_merge",
            "strandedness_clash",
            "initial_bam_name",
            "additional_bam_name",
            "sexdet_bam_name",
            "Sample_ID",
            "id",
            "poseidon_IDs",
        ],
        axis=1,
    )
    .drop_duplicates()
)

summarised_stats = pd.DataFrame()
summarised_stats["Sample_Name"] = compound_eager_table["Sample_Name"].unique()
## Contamination_Note: Add note about contamination estimation in libraries with more SNPs than the cutoff.
summarised_stats = (
    compound_eager_table.astype("string")
    .groupby("Sample_Name")[["Contamination_Nr_SNPs"]]
    .agg(
        lambda x: "Nr Snps (per library): {}. Estimate and error are weighted means of values per library. Libraries with fewer than 100 SNPs used in contamination estimation were excluded.".format(
            ";".join(x)
        )
    )
    .rename(columns={"Contamination_Nr_SNPs": "Contamination_Note"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## Add library names
compound_eager_table["Original_library_names"] = compound_eager_table.apply(
    infer_library_name, axis=1, args=("Sample_Name", "Library_ID")
)
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")[["Original_library_names"]]
    .agg(lambda x: ";".join(x))
    .rename(columns={"Original_library_names": "Library_Names"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## Nr_Libraries: Count number of libraries per sample
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")[["Library_ID"]]
    .agg("nunique")
    .rename(columns={"Library_ID": "Nr_Libraries"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## UDG: Add UDG info by aggregating info to poseidon_ID level.
## If more than one unique state exists in a group, return `mixed`
agg_func = lambda group: group.iloc[0] if group.nunique() == 1 else "mixed"
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")[["UDG_Treatment"]]
    .agg({"UDG_Treatment": agg_func})
    .apply(udg_treatment_to_udg, axis=1)
    .rename(columns={"UDG_Treatment": "UDG"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## Library_Built & CaptureType (inference is not great though)
summarised_stats = (
    library_built_table.groupby("poseidon_IDs")[["library_built", "library_strategy"]]
    .agg({"library_built": agg_func, "library_strategy": lambda x: ";".join(x)})
    .merge(
        summarised_stats,
        right_on="Sample_Name",
        left_on="poseidon_IDs",
        validate="one_to_one",
    )
    .rename(
        columns={"library_built": "Library_Built", "library_strategy": "Capture_Type"}
    )
)

## Contamination_Est: Calculated weighted mean across libraries of a sample.
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")[
        ["Contamination_Nr_SNPs", "Contamination_Est", "Contamination_SE", "n_reads"]
    ]
    .apply(
        weighted_mean,
        wt_col="n_reads",
        val_col="Contamination_Est",
        filter_col="Contamination_Nr_SNPs",
        min_val=100,
    )
    .reset_index("Sample_Name")
    .rename(columns={0: "Contamination"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## Contamination_SE: Calculated weighted mean across libraries of a sample.
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")[
        ["Contamination_Nr_SNPs", "Contamination_Est", "Contamination_SE", "n_reads"]
    ]
    .apply(
        weighted_mean,
        wt_col="n_reads",
        val_col="Contamination_SE",
        filter_col="Contamination_Nr_SNPs",
        min_val=100,
    )
    .reset_index("Sample_Name")
    .rename(columns={0: "Contamination_Err"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## Contamination_Meas: If Contamination column is not empty, add the contamination measure
summarised_stats["Contamination_Meas"] = summarised_stats.apply(
    set_contamination_measure, axis=1
)

## Damage: Calculated weighted mean across libraries of a sample.
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")[["damage", "n_reads"]]
    .apply(
        weighted_mean,
        wt_col="n_reads",
        val_col="damage",
        filter_col="n_reads",
        min_val=0,
    )  ## filter on n_reads >= 0, i.e. no filtering.
    .reset_index("Sample_Name")
    .rename(columns={0: "Damage"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

## Endogenous: The maximum value of endogenous DNA across WGS libraries of a sample.
summarised_stats = (
    compound_eager_table.groupby("Sample_Name")["endogenous"]
    .apply(
        max,
    )
    .reset_index("Sample_Name")
    .rename(columns={"endogenous": "Endogenous"})
    .merge(summarised_stats, on="Sample_Name", validate="one_to_one")
)

final_eager_table = (
    compound_eager_table.merge(
        summarised_stats, on="Sample_Name", validate="many_to_one"
    )
    .drop(
        columns=[
            "Library_ID",
            "Contamination_Nr_SNPs",
            "Contamination_Est",
            "Contamination_SE",
            "n_reads",
            "damage",
            "endogenous",
            "UDG_Treatment",
            "Original_library_names",
        ],
    )
    .drop_duplicates()
)
## Dropping duplicates here is necessary when Nr_Libraries is >1, as the same Sample_Name will be repeated for each library.

filled_janno_table = janno_table.merge(
    final_eager_table, left_on="Eager_ID", right_on="Sample_Name"
)
## Replace columns in original janno with values in final_eager_table
## TODO-dev need to infer Genetic_Sex from 'RateX', 'RateY', 'RateErrX', 'RateErrY'
for col in [
    "Nr_SNPs",
    "Damage",
    "Contamination_Err",
    "Contamination",
    "Nr_Libraries",
    "Contamination_Note",
    "Library_Names",
    "Contamination_Meas",
    "Endogenous",
    "Library_Built",
    "Capture_Type",
    "UDG",
    "Genetic_Source_Accession_IDs",
]:
    filled_janno_table[col] = (
        filled_janno_table[[col + "_x", col + "_y"]].bfill(axis=1).iloc[:, 0]
    )

## Drop columns duplicated from merges, and columns that are not relevant anymore.
filled_janno_table = filled_janno_table.drop(
    list(filled_janno_table.filter(regex=r".*_(x|y)")), axis=1
).drop("Sample_Name", axis=1)

## Replace NAs with "n/a"
filled_janno_table.replace(np.nan, "n/a", inplace=True)

## Infer the eager version from software_versions.csv in the nf-core/eager result directory.
EAGER_VERSION = get_eager_version(args.eager_result_dir)
filled_janno_table["Data_Preparation_Pipeline_URL"] = (
    f"https://github.com/nf-core/eager/releases/tag/{EAGER_VERSION}"
)
filled_janno_table["Genotype_Ploidy"] = "haploid"

final_column_order = [
    "Poseidon_ID",
    "Genetic_Sex",
    "Group_Name",
    "Alternative_IDs",
    "Main_ID",  ## Added
    "Relation_To",
    "Relation_Degree",
    "Relation_Type",
    "Relation_Note",
    "Collection_ID",
    "Country",
    "Country_ISO",
    "Location",
    "Site",
    "Latitude",
    "Longitude",
    "Date_Type",
    "Date_C14_Labnr",
    "Date_C14_Uncal_BP",
    "Date_C14_Uncal_BP_Err",
    "Date_BC_AD_Start",
    "Date_BC_AD_Median",
    "Date_BC_AD_Stop",
    "Date_Note",
    "MT_Haplogroup",
    "Y_Haplogroup",
    "Source_Tissue",
    "Nr_Libraries",
    "Library_Names",
    "Capture_Type",
    "UDG",
    "Library_Built",
    "Genotype_Ploidy",
    "Data_Preparation_Pipeline_URL",
    "Endogenous",
    "Nr_SNPs",
    "Coverage_on_Target_SNPs",
    "Damage",
    "Contamination",
    "Contamination_Err",
    "Contamination_Meas",
    "Contamination_Note",
    "Genetic_Source_Accession_IDs",
    "Primary_Contact",
    "Publication",
    "Note",
    "Keywords",
    "Eager_ID",  ## Added
    "RateX",  ## Added
    "RateY",  ## Added
    "RateErrX",  ## Added
    "RateErrY",  ## Added
]

## Reorder columns to match desired order
filled_janno_table = filled_janno_table[final_column_order]

if args.safe:
    out_fn = f"{poseidon_yaml_data.janno_file}.new"
    print(f"Safe mode is activated. Results saved in: {out_fn}")
    filled_janno_table.to_csv(out_fn, sep="\t", index=False)
else:
    filled_janno_table.to_csv(poseidon_yaml_data.janno_file, sep="\t", index=False)
