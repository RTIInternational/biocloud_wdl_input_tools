#!/usr/bin/env python3

import argparse
import logging
import sys
import json
import time
import shutil
import pandas as pd

import wdl_input_tools.core as wdl
import wdl_input_tools.helpers as utils
import wdl_input_tools.cli as cli


def get_argparser():
    # Configure and return argparser object for reading command line arguments
    argparser_obj = argparse.ArgumentParser(prog="make_batch_inputs")

    # Path to batch config file
    argparser_obj.add_argument("--batch-config",
                               action="store",
                               type=cli.file_type_arg,
                               dest="batch_config_file",
                               required=True,
                               help="Path to batch config yaml file")

    # Path to sample sheet excel file
    argparser_obj.add_argument("--sample-sheet",
                               action="store",
                               type=cli.file_type_arg,
                               dest="sample_sheet_file",
                               required=True,
                               help="Path to sample sheet that will be used to populate WDL template")

    # Batch name to be associated with all workflows
    argparser_obj.add_argument("--batch-name",
                               action="store",
                               type=cli.batch_type_arg,
                               dest="batch_name",
                               required=True,
                               help="Name to associate with batch of workflows")

    # Output prefix
    argparser_obj.add_argument("--output-dir",
                               action="store",
                               type=cli.dir_type_arg,
                               dest="output_dir",
                               required=True,
                               help="Output dir where batch input and config record files will be generated.")

    # Retained for compatibility with older command lines.
    argparser_obj.add_argument("--force",
                               action="store_true",
                               dest="force_overwrite",
                               help="Deprecated compatibility flag. Ignored.")

    # Verbosity level
    argparser_obj.add_argument("-v",
                               action='count',
                               dest='verbosity_level',
                               required=False,
                               default=0,
                               help="Increase verbosity of the program."
                                    "Multiple -v's increase the verbosity level:\n"
                                    "0 = Errors\n"
                                    "1 = Errors + Warnings\n"
                                    "2 = Errors + Warnings + Info\n"
                                    "3 = Errors + Warnings + Info + Debug")

    return argparser_obj

def main():

    # Configure argparser
    argparser = get_argparser()

    # Parse the arguments
    args = argparser.parse_args()

    # Input files: json input file to be used as template and
    batch_config_file = args.batch_config_file
    ss_file  = args.sample_sheet_file
    batch_name = args.batch_name
    output_dir = args.output_dir
    _force_overwrite = args.force_overwrite

    # Configure logging appropriate for verbosity
    utils.configure_logging(args.verbosity_level)

    # Read in batch configuration options from yaml file
    batch_config = wdl.BatchConfig(batch_config_file)

    # Read in sample sheet from excel file
    sample_sheet = wdl.InputSampleSheet(ss_file, sample_id_col=batch_config.sample_id_col)

    # Validate sample sheet using validation functions specified in batch config file
    batch_config.validate_sample_sheet(sample_sheet)

    # Convert sample sheet to WDL json inputs
    wdl_template = batch_config.batch_wdl_template

    if batch_config.wf_type == "scatter":
        # Scatter workflows convert ss to list of jsons where each row is input to separate wf (e.g. RNAseq wf)
        logging.info("Generating workflow inputs json...")
        ss_inputs = sample_sheet.sample_sheet.to_dict(orient="records")
        inputs_json = [wdl_template.make_wf_input(ss_input) for ss_input in ss_inputs]

    elif batch_config.wf_type == "gather":
        # Gather workflows convert ss to single json
        # Each column passed to one wf key as a list (e.g. merge RNAseq wf)
        logging.info("Generating workflow inputs json...")
        inputs_json = sample_sheet.sample_sheet.to_dict(orient="list")
        inputs_json = wdl_template.make_wf_input(inputs_json)

    # Write batch output files
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    output_prefix = "{0}/{1}".format(output_dir, batch_name)
    batch_inputs_file = "{0}.make_batch.inputs.{1}.json".format(output_prefix, timestamp)
    batch_config_record_file = "{0}.make_batch.config.{1}.yaml".format(output_prefix, timestamp)

    # Write batch inputs to json file
    with open(batch_inputs_file, "w", encoding="utf-8") as fh:
        json.dump(inputs_json, fh, indent=1, cls=utils.NpEncoder)

    # Write record of batch config so we know how this set of inputs was created
    shutil.copy(batch_config_file, batch_config_record_file)


if __name__ == "__main__":
    sys.exit(main())
