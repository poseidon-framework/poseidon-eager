#!/usr/bin/env python3

## Script originally made by Stephan Schiffels (@stschiff). Edited by Thiseas C. Lamnidis (@TCLamnidis) for specific use in this repository.

import sys
import argparse
import os
import wget

parser = argparse.ArgumentParser(
    prog = 'download_ena_data',
    description = 'This script downloads raw FASTQ data from the ENA, using '
                  'links to the raw data and metadata provided by a Poseidon-'
                  'formatted sequencingSourceFile')

parser.add_argument('-d', '--ssf_dir', metavar="<DIR>", required=True, help="The directory to scan for poseidon-formatted sequencingSourceFiles, to download the described data.")
parser.add_argument('-o', '--output_dir', metavar="<DIR>", required=True, help="The output directory for the FASTQ files.")
parser.add_argument('--dry_run', action='store_true', help="Only list the download commands, but don't do anything.")

def read_ena_table(file_name):
    l = file_name.readlines()
    headers = l[0].split()
    return map(lambda row: dict(zip(headers, row.split('\t'))), l[1:])

args = parser.parse_args()

# os.path.abspath(args.sequencingSourceFile) ## Absolute path to ssf file.
print("[download_ena_data.py]: Scanning for poseidon sequencingSource files", file=sys.stderr)

for root, dirs, files in os.walk( os.path.join(args.ssf_dir) ):
    for file_name in files:
        if file_name.endswith(".ssf"):
            source_file = os.path.join(root, file_name)
            print("[download_ena_data.py]: Found Sequencing Source File: ", source_file, file=sys.stderr)
            package_name = os.path.splitext(file_name)[0] ## The SSF name and desired package name must match
            odir = os.path.join(args.output_dir, package_name)
            os.makedirs(odir, exist_ok=True)
            line_count=1
            with open(source_file, 'r') as f:
                md5_fn=open(os.path.join(odir,"expected_md5sums.txt"), 'w')
                for ena_entry in read_ena_table(f):
                    line_count+=1
                    fastq_url = ena_entry["fastq_ftp"]
                    if fastq_url == '':
                        run_accession = ena_entry["run_accession"]
                        print(f"[download_ena_data.py]: No 'fastq_ftp' entry found for {run_accession} @ line {line_count}. Skipping", file=sys.stderr)
                        continue
                    fastq_filename = os.path.basename(fastq_url)
                    target_file = os.path.join(odir, fastq_filename)
                    fastq_md5=ena_entry["fastq_md5"]
                    if os.path.isfile(target_file):
                        print(f"[download_ena_data.py]: Target file {target_file} already exists. Skipping", file=sys.stderr)
                        print(f"{fastq_md5}  {target_file}", file=md5_fn) ## expected md5sums should always be updated even if the file has already been downloaded.
                    else:
                        print(f"[download_ena_data.py]: Downloading {fastq_url} into {target_file}", file=sys.stderr)
                        if not args.dry_run:
                            wget.download("https://" + fastq_url, out=target_file)
                            print(f"{fastq_md5}  {target_file}", file=md5_fn)


