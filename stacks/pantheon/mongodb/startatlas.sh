#!/bin/bash

# Run the command and save the output
OUTPUT=$(atlas deployments list)
echo "Output: $OUTPUT"

# Count lines of output
LINE=$(echo "$OUTPUT" | wc -l)
echo "Count line of output: $LINE"

if [ $LINE -lt 2 ]; then
    echo "No deployment found. Creating a new one."
    atlas deployments setup $MONGO_INITDB_DATABASE --bindIpAll --username $MONGO_INITDB_ROOT_USERNAME --password $MONGO_INITDB_ROOT_PASSWORD --type local --force
else
    echo "Deployment found. Starting it."
    atlas deployments start $MONGO_INITDB_DATABASE
fi

function pause_atlas() {
    atlas deployments pause $MONGO_INITDB_DATABASE
}

# Set trap to pause atlas on exit
trap pause_atlas EXIT

tail -f /dev/null
