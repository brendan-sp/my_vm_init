#!/bin/bash
# Wrapper that shuts down the VM if a command fails after running
# longer than a specified minimum time.
#
# Usage: ./run_and_shutdown_on_fail.sh <min_runtime_minutes> <command...>
# Example: ./run_and_shutdown_on_fail.sh 20 ./run.sh --stage 5 --stop_stage 5 ...
#
# If <command> exits with a non-zero code AND ran for longer than
# <min_runtime_minutes>, the VM is shut down after a 60-second grace period.

MIN_MINUTES="${1:?Usage: $0 <min_minutes> <command...>}"
shift

if [ $# -eq 0 ]; then
    echo "Error: no command specified"
    echo "Usage: $0 <min_minutes> <command...>"
    exit 1
fi

START_TIME=$(date +%s)

"$@"
EXIT_CODE=$?

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC=$(( ELAPSED % 60 ))

echo "Command exited with code $EXIT_CODE after ${ELAPSED_MIN}m ${ELAPSED_SEC}s"

if [ "$EXIT_CODE" -ne 0 ] && [ "$ELAPSED" -gt $(( MIN_MINUTES * 60 )) ]; then
    echo "Process failed after >${MIN_MINUTES} minutes. Shutting down VM in 60 seconds..."
    sleep 60
    sudo shutdown -h now
elif [ "$EXIT_CODE" -ne 0 ]; then
    echo "Process failed but only ran for ${ELAPSED_MIN}m ${ELAPSED_SEC}s (<${MIN_MINUTES}m). NOT shutting down."
else
    echo "Process completed successfully. NOT shutting down."
fi

exit $EXIT_CODE
