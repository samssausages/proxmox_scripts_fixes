#!/bin/bash

# Directory containing your backup scripts
SCRIPTS_DIR="/usr/local/bin/backups"

# Change to the directory
cd "$SCRIPTS_DIR"

# Find and run each script in the directory sequentially
for script in $(ls); do
    if [[ -x "$script" && -f "$script" ]]; then
        echo "Running $script..."
        ./"$script"
    else
        echo "Skipping $script: not an executable file."
    fi
done