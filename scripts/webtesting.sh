#!/usr/bin/env bash
# Set options for improved error handling:
set -Eeuo pipefail
export SHELLOPTS

error_handler() {
    echo "$0: Error occurred on line $1"
    echo "Exiting with status $2"
    exit $2
}

trap 'error_handler $LINENO $? $0' ERR

while true; do
	for i in {1..4}; do
		curl "http://localhost:8080/test$i" &
		sleep .254
	done
	wait
	sleep 1
	date
done
