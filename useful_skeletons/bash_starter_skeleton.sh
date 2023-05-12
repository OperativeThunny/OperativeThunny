#!/usr/bin/env bash
#
# This is an example skeleton to use for writing a general purpose bash script.
# Replace this text with a detailed explanation of the goal of the script.
#
# Author: @OperativeThunny
# Date: 12 May 2023
##
# This script is licensed under the GNU Affero General Public License, version 3.0 (AGPLv3).
#
# A copy of the AGPLv3 license can be found at:
# https://www.gnu.org/licenses/agpl-3.0.html

# Set options for improved error handling
set -Eeou pipefail

# Set variables
export PROG_NAME="Program_or_script_name_goes_here";
export LOGFILE="/opt/${PROG_NAME}/${PROG_NAME}.log"

# Redirect all output to the log file
exec > $LOGFILE 2>&1

# Function to handle errors
error_handler() {
    echo "$0: Error occurred on line $1"
    echo "Exiting with status $2"
    exit $2
}

# Trap errors and call the error handler function
trap 'error_handler $LINENO $? $0' ERR

# Script code goes here!
