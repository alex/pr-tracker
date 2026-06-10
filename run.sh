#!/bin/sh
# Build and launch PR Tracker.
set -eu
cd "$(dirname "$0")"

./build.sh
open "build/PR Tracker.app"
