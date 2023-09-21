#!/usr/bin/env bash
#
# This is an example skeleton to use for writing a general purpose bash script.
# Replace this text with a detailed explanation of the goal of the script.
#
# Author: @OperativeThunny
# Date: 12 May 2023
# Updated: 23 May 2023
##
# This script is licensed under the GNU Affero General Public License, version 3.0 (AGPLv3).
#
# A copy of the AGPLv3 license can be found at:
# https://www.gnu.org/licenses/agpl-3.0.html
##
# See https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html for an explanation of `set` options.
#
# -E If set, any trap on ERR is inherited by shell functions, command
#    substitutions, and commands executed in a subshell environment. The ERR
#    trap is normally not inherited in such cases.
# -e Exit immediately if a pipeline (see Pipelines), which may consist of a single simple command, a list,
#    or a compound command returns a non-zero status. See the documentation for a much larger explanation.
# -u Treat unset variables and parameters other than the special parameters ‘@’ or ‘*’, or array variables subscripted
#    with ‘@’ or ‘*’, as an error when performing parameter expansion. An error message will be written to the standard
#    error, and a non-interactive shell will exit.
# -o option-name
#    Set the option corresponding to option-name:
#   errexit Same as -e.
#   errtrace Same as -E.
#   nounset Same as -u.
#   pipefail
#       If set, the return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero
#       status, or zero if all commands in the pipeline exit successfully. This option is disabled by default.
#
#  The current set of options may be found in $-.

# Set options for improved error handling:
set -Eeuo pipefail

# Debugging options:
# -v Print shell input lines as they are read.
# -x Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and
#    their arguments or associated word lists after they are expanded and before they are executed. The value of the
#    PS4 variable is expanded and the resultant value is printed before the command and its expanded arguments.
#set -xv # Uncomment for debugging.
# -n Read commands but do not execute them. This may be used to check a script for syntax errors. This option is ignored by interactive shells.
#set -n

# Set variables
export PROG_NAME="Program_or_script_name_goes_here";
export LOGFILE="/opt/${PROG_NAME}/${PROG_NAME}.log"

# Redirect all output to the log file
exec > $LOGFILE 2>&1

# # wow this is cool, it sends stdout and stderr to syslog and I can see it with
# # journalctl -f -t bash_starter_skeleton.sh and I had no idea this was possible
# # until I saw it in suggested code from copilot
#exec 1> >(logger -s -t $(basename $0)) 2>&1

# Function to handle errors
error_handler() {
    echo "$0: Error occurred on line $1"
    echo "Exiting with status $2"
    exit $2
}

# Trap errors and call the error handler function
trap 'error_handler $LINENO $? $0' ERR

# Script code goes here!
