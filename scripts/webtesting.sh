#!/usr/bin/env bash
# Set options for improved error handling:
set -xvEeuo pipefail

while true; do
	for i in {1..4}; do
		curl "http://localhost:8080/test$i" &
	done
	wait
	sleep 1
done
