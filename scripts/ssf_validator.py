#!/usr/bin/env python

# MIT License (c) 2023 Thiseas C. Lamnidis

VERSION="0.2.0dev"

import os
import sys
import errno
import argparse


def read_ssf_file(file_name, required_fields=None, error_counter=0):
    l = file_name.readlines()
    headers = l[0].split()
    if required_fields:
        for field in required_fields:
            if field not in headers:
                error_counter = print_error(
                    "Required field '{}' not found in header!".format(field), "", "", error_counter
                )
        if error_counter > 0:
            print(
                "[Column existence check] {} formatting error(s) were detected in the input SSF file.".format(error_counter)
            )
            sys.exit(1)
    return map(lambda row: dict(zip(headers, row.split('\t'))), l[1:])


def isNAstr(var):
    x = False
    if isinstance(var, str) and var == "n/a":
        x = True
    return x


def parse_args(args=None):
    Description = "Validate a poseidon-formatted SSF file for use by the Minotaur pipeline."
    Epilog = "Example usage: python ssf_validator.py <FILE_IN>"

    parser = argparse.ArgumentParser(description=Description, epilog=Epilog)
    parser.add_argument("FILE_IN", help="Input SSF file.")
    return parser.parse_args(args)


def make_dir(path):
    if len(path) > 0:
        try:
            os.makedirs(path)
        except OSError as exception:
            if exception.errno != errno.EEXIST:
                raise exception


def print_error(error, context="Line", context_str="", error_counter=0):
    if isinstance(context_str, str):
        context_str = "'{}'".format(context_str.strip())
    error_str = "[ssf_validator.py] Error in SSF file: {}".format(error)
    if context != "" and context_str != "":
        error_str = "[ssf_validator.py] Error in SSF file @ {} {}: {}".format(
            context.strip(), context_str, error
        )
    print(error_str)
    error_counter += 1
    return error_counter


def validate_poseidon_ids(poseidon_ids, error_counter, line_num):
    ## Poseidon IDs should not end in ';'
    ##   If a list, the `;` will be within the field, not at the end. If a single value, it should not have `;` at all.
    if poseidon_ids.endswith(";"):
        error_counter = print_error("poseidon_ids cannot end in ';'.", "Line", line_num, error_counter)

    ## Poseidon IDs cannot be missing or 'n/a'
    if not poseidon_ids:
        error_counter = print_error("poseidon_ids entry has not been specified!", "Line", line_num, error_counter)
    elif isNAstr(poseidon_ids):
        error_counter = print_error("poseidon_ids cannot be 'n/a'!", "Line", line_num, error_counter)
    
    return(error_counter)


def validate_instrument_model(instrument_model, error_counter, line_num):
    two_chem_seqs = [
        "NextSeq 1000",
        "NextSeq 500",
        "NextSeq 550",
        "Illumina NovaSeq 6000",
        "Illumina MiniSeq",
    ]
    four_chem_seqs = [
        "Illumina HiSeq 1000",
        "Illumina HiSeq 1500",
        "Illumina HiSeq 2000",
        "Illumina HiSeq 2500",
        "Illumina HiSeq 3000",
        "Illumina HiSeq 4000",
        "Illumina HiSeq X",
        "HiSeq X Five",
        "HiSeq X Ten",
        "Illumina Genome Analyzer",
        "Illumina Genome Analyzer II",
        "Illumina Genome Analyzer IIx",
        "Illumina HiScanSQ",
        "Illumina MiSeq",
    ]

    if instrument_model not in two_chem_seqs + four_chem_seqs:
        error_counter = print_error(
            "instrument_model '{}' is not recognised as one that can be processed with nf-core/eager. Options: {}".format(
                instrument_model,
                ", ".join(two_chem_seqs + four_chem_seqs)
            ),
            "Line",
            line_num,
            error_counter,
        )


def validate_ssf(file_in):
    """
    This function checks that the SSF file contains all the expected columns, and validated the entries in the columns needed for Minotaur processing.
    """

    error_counter = 0
    with open(file_in, "r") as fin:
        ## Check header
        MIN_COLS = 7 ## Minimum number of non missing columns
        HEADER = [
            "poseidon_IDs",                 ## Required
            "udg",                          ## Required
            "library_built",                ## Required
            "sample_accession",
            "study_accession",
            "run_accession",
            "sample_alias",
            "secondary_sample_accession",
            "first_public",
            "last_updated",
            "instrument_model",             ## Required
            "library_layout",
            "library_source",
            "instrument_platform",          ## Required
            "library_name",                 ## Required
            "library_strategy",
            "fastq_ftp",                    ## Required
            "fastq_aspera",
            "fastq_bytes",
            "fastq_md5",
            "read_count",
            "submitted_ftp"
        ]

        ## Check entries
        for line_num, ssf_entry in enumerate(read_ssf_file(fin)):
            line_num += 2  ## From 0-based to 1-based. Add an extra 1 for the header line

            # Check valid number of columns per row
            if len(ssf_entry) < len(HEADER):
                error_counter = print_error(
                    "Invalid number of columns (minimum = {})!".format(len(HEADER)), "Line", line_num, error_counter
                )
            ## Check number of non n/a columns per row
            num_cols = len([x for x in ssf_entry if x])
            if num_cols < MIN_COLS:
                error_counter = print_error(
                    "Invalid number of populated columns (minimum = {})!".format(MIN_COLS), "Line", line_num, error_counter
                )

            ## Validate poseidon IDs
            validate_poseidon_ids(ssf_entry["poseidon_IDs"], error_counter, line_num)

            ## Validate UDG
            if ssf_entry["udg"] not in ["minus", "half", "plus"]:
                error_counter = print_error(
                    "udg entry is not recognised. Options: minus, half, plus.",
                    "Line",
                    line_num,
                    error_counter,
                )
            
            ## Validate library_built
            if ssf_entry["library_built"] not in ["ds", "ss"]:
                error_counter = print_error(
                    "library_built entry is not recognised. Options: ds, ss.",
                    "Line",
                    line_num,
                    error_counter,
                )
            
            ## Validate instrument_model
            validate_instrument_model(ssf_entry["instrument_model"], error_counter, line_num)

            ## Validate instrument_platform
            if ssf_entry["instrument_platform"] not in ["ILLUMINA"]:
                error_counter = print_error(
                    "instrument_platform entry is not recognised. Options: ILLUMINA.",
                    "Line",
                    line_num,
                    error_counter,
                )

            ## Validate library_name
            if not ssf_entry["library_name"]:
                error_counter = print_error("library_name entry has not been specified!", "Line", line_num, error_counter)
            elif isNAstr(ssf_entry["library_name"]):
                error_counter = print_error("library_name cannot be 'n/a'!", "Line", line_num, error_counter)

            ## Validate fastq_ftp
            for reads in [ ssf_entry["fastq_ftp"] ]:
                ## Can be empty string in some cases where input is a BAM, but then data won't be processes (atm)
                if isNAstr(reads):
                    error_counter = print_error("fastq_ftp cannot be 'n/a'!", "Line", line_num, error_counter)
                elif reads.find(" ") != -1:
                        error_counter = print_error(
                            "File names cannot contain spaces! Please rename.", "Line", line_num, error_counter
                        )
                ## Check that the fastq_ftp entry ends with a valid extension
                elif (
                    not reads.endswith(".fastq.gz")
                    and not reads.endswith(".fq.gz")
                    and not reads.endswith(".fastq")
                    and not reads.endswith(".fq")
                    and not reads == ""
                ):
                    error_counter = print_error(
                        "FASTQ file(s) have unrecognised extension. Allowed extensions: .fastq.gz, .fq.gz, .fastq, .fq!",
                        "Line",
                        line_num,
                        error_counter,
                    )

    ## If formatting errors have occurred print their number and fail.
    if error_counter > 0:
        print(
            "[Formatting check] {} formatting error(s) were detected in the input file. Please check samplesheet.".format(
                error_counter
            )
        )
        sys.exit(1)
    ## if no formatting errors have occurred, print success message and exit.
    else:
        print("[Formatting check] No formatting errors were detected in the input file.")
        sys.exit(0)

def main(args=None):
    args = parse_args(args)
    validate_ssf(args.FILE_IN)


if __name__ == "__main__":
    print("[ssf_validator.py]: version {}".format(VERSION), file=sys.stderr)
    sys.exit(main())
