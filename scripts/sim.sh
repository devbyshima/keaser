#!/bin/bash
# Prints the UDID of the simulator named $SIM, creating it first if needed
# (iPhone 16 Pro, the 402x874pt screen the reference recording was made on).
# Builders running in parallel each use their own SIM name.
set -euo pipefail
SIM="${SIM:-Keaser iPhone 16 Pro}"
TYPE="${SIM_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro}"
RUNTIME="${SIM_RUNTIME:-$(xcrun simctl list runtimes -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS' and x['isAvailable']];print(r[-1]['identifier'])")}"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for rt, devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if d['name'] == '''$SIM''': print(d['udid']); sys.exit()
")
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl create "$SIM" "$TYPE" "$RUNTIME")
fi
echo "$UDID"
