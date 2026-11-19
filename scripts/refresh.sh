#!/bin/zsh
# ios-live-preview: puts the latest build of an iOS app in front of you, in three places at once:
#
#   <Name> Light   a simulator in light mode
#   <Name> Dark    a simulator in dark mode
#   your iPhone    the app (and its App Clip, if it has one)
#
# Run it from the project's folder. It reads `.ios-preview` there (shell variables, below), creates the two simulators
# if they are missing, boots them, shuts down any other simulator that is running (other projects' Light and Dark pairs excepted), builds the app from the working tree, installs and launches it in both, then builds
# and installs the app (and the Clip) on the first iPhone connected. A phone that can't be reached is a note at the end,
# never a failure: the simulators are refreshed all the same.
#
#   refresh.sh             build, install and launch everywhere
#   refresh.sh --no-build  reinstall the last simulator build (the phone skipped)
#   refresh.sh --no-phone  the simulators only
#
# `.ios-preview`:
#   SCHEME="MyApp"                  the app's scheme (required)
#   NAME="MyApp"                    the simulators' names: "<NAME> Light", "<NAME> Dark" (default: SCHEME)
#   WORKSPACE="MyApp.xcworkspace"   or PROJECT="MyApp.xcodeproj" (default: whatever xcodebuild finds)
#   CLIP_SCHEME="MyApp Clip"        an App Clip to put on the phone after the app (optional)
#   LAUNCH_ARGS=(-demo YES)         arguments the app is launched with in the simulators (optional)
#   DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"   (default: the newest iPhone Pro)
#   PHONE="<udid>"                  which iPhone, with more than one connected (default: the first)
set -euo pipefail

config=".ios-preview"
[[ -f "$config" ]] || { echo "no $config here: run from the project's folder, or create one (see the top of $0)" >&2; exit 2; }
SCHEME="" NAME="" WORKSPACE="" PROJECT="" CLIP_SCHEME="" DEVICE_TYPE="" PHONE=""
LAUNCH_ARGS=()
source "./$config"
[[ -n "$SCHEME" ]] || { echo "$config sets no SCHEME" >&2; exit 2; }
NAME="${NAME:-$SCHEME}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

build=1 phone=1
for arg in "$@"; do
    case "$arg" in
        --no-build) build=0; phone=0 ;;
        --no-phone) phone=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

container=()
[[ -n "$WORKSPACE" ]] && container=(-workspace "$WORKSPACE")
[[ -n "$PROJECT" ]] && container=(-project "$PROJECT")
derived="$HOME/Library/Developer/Xcode/DerivedData/ios-live-preview-$(echo "$PWD" | shasum | cut -c1-8)"

# A setting of a scheme's built product, for a platform ("iOS Simulator" or "iOS").
setting() {
    xcodebuild "${container[@]}" -scheme "$1" -configuration Debug -destination "generic/platform=$2" \
        -derivedDataPath "$derived" -showBuildSettings -json 2> /dev/null | /usr/bin/python3 -c '
import json, sys
for target in json.load(sys.stdin):
    s = target["buildSettings"]
    if s.get("WRAPPER_EXTENSION") == "app":
        print(s[sys.argv[1]]); break
' "$3"
}

# The newest iOS runtime, and the newest iPhone Pro, for a simulator that has to be created.
runtime=$(xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
rs.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")
')
[[ -n "$runtime" ]] || { echo "no iOS simulator runtime installed (Xcode › Settings › Components)" >&2; exit 1; }
DEVICE_TYPE="${DEVICE_TYPE:-$(xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json, re, sys
types = [t for t in json.load(sys.stdin)["devicetypes"] if re.fullmatch(r"iPhone \d+ Pro", t["name"])]
types.sort(key=lambda t: int(re.search(r"\d+", t["name"]).group()))
print(types[-1]["identifier"] if types else "")
')}"

# The simulator with this name, created if there is none.
udid_for() {
    local udid
    udid=$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == sys.argv[1] and d["isAvailable"]:
            print(d["udid"]); sys.exit()
' "$1")
    if [[ -z "$udid" ]]; then
        udid=$(xcrun simctl create "$1" "$DEVICE_TYPE" "$runtime")
        echo "created $1 ($udid)" >&2
    fi
    echo "$udid"
}

light=$(udid_for "$NAME Light")
dark=$(udid_for "$NAME Dark")
for udid in $light $dark; do
    xcrun simctl bootstatus "$udid" -b > /dev/null
done
xcrun simctl ui "$light" appearance light
xcrun simctl ui "$dark" appearance dark

# Only these two run, besides other projects' live-preview pairs. Another booted simulator (one Xcode's Run button, a
# preview or another session started) can take one of their places in a simulator panel when it reconnects, for
# instance after the Mac's display has slept. A simulator of a pair named "<Other> Light" and "<Other> Dark" is another
# project's live preview and is left alone.
xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
devices = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds]
booted = [d for d in devices if d["state"] == "Booted"]
names = {d["name"] for d in devices}
def preview_pair(name):  # one of a pair "<Name> Light" and "<Name> Dark": another project, left alone
    return any(name.endswith(a) and name[: -len(a)] + b in names for a, b in ((" Light", " Dark"), (" Dark", " Light")))
for d in booted:
    if d["udid"] not in sys.argv[1:] and not preview_pair(d["name"]):
        print(d["udid"] + "\t" + d["name"])
' "$light" "$dark" | while IFS=$'\t' read -r other other_name; do
    xcrun simctl shutdown "$other" && echo "shut down $other_name ($other): not $NAME Light or Dark, nor a live-preview pair" >&2
done

if (( build )); then
    echo "building $SCHEME" >&2
    xcodebuild "${container[@]}" -scheme "$SCHEME" -configuration Debug -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$derived" build -quiet
fi
bundle=$(setting "$SCHEME" "iOS Simulator" PRODUCT_BUNDLE_IDENTIFIER)
app="$derived/Build/Products/Debug-iphonesimulator/$(setting "$SCHEME" "iOS Simulator" FULL_PRODUCT_NAME)"
[[ -d "$app" ]] || { echo "no build found at $app; run without --no-build" >&2; exit 1; }

for udid in $light $dark; do
    xcrun simctl terminate "$udid" "$bundle" 2> /dev/null || true
    # A simulator just booted can refuse its first install while its home screen settles; it takes the next one.
    for attempt in 1 2 3 4 5; do
        xcrun simctl install "$udid" "$app" 2> /dev/null && break
        (( attempt == 5 )) && xcrun simctl install "$udid" "$app"
        sleep 3
    done
    xcrun simctl launch "$udid" "$bundle" "${LAUNCH_ARGS[@]}" > /dev/null
done

commit="$(git rev-parse --short HEAD 2> /dev/null || echo 'no git')$(git diff --quiet 2> /dev/null || echo ' with uncommitted changes')"
echo "$NAME Light $light, $NAME Dark $dark: running $commit"

# The phone. Any failure here is a note, not an error.
(( phone )) || exit 0
device="$PHONE"
if [[ -z "$device" ]]; then
    json=$(mktemp)
    xcrun devicectl list devices --json-output "$json" > /dev/null 2>&1 || true
    device=$(/usr/bin/python3 -c '
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit()
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical" and hw.get("deviceType") == "iPhone":
        print(hw.get("udid", "")); break
' "$json")
    rm -f "$json"
fi
[[ -n "$device" ]] || { echo "NOTE phone: no iPhone paired with this Mac; the phone was not updated"; exit 0; }

note() {
    echo "NOTE phone: $1 (keep the phone on the same network or a cable, paired and trusted, and run it again)"
    exit 0
}
# Over Wi-Fi an idle phone is listed as unavailable and xcodebuild gives up on it; a direct request wakes it.
xcrun devicectl device info details --device "$device" > /dev/null 2>&1 || true
log="$derived-phone.log"
to_phone() {
    local scheme="$1" product
    echo "building $scheme for the phone" >&2
    xcodebuild "${container[@]}" -scheme "$scheme" -configuration Debug -destination "id=$device" \
        -allowProvisioningUpdates -derivedDataPath "$derived" build -quiet > "$log" 2>&1 \
        || note "the build of $scheme for the phone failed, nothing on it was updated (see $log)"
    product="$derived/Build/Products/Debug-iphoneos/$(setting "$scheme" "iOS" FULL_PRODUCT_NAME)"
    xcrun devicectl device install app --device "$device" "$product" > "$log" 2>&1 \
        || note "installing $scheme on the phone failed (see $log)"
}
to_phone "$SCHEME"
# The App Clip after the app, every time: installing the full app removes its Clip.
[[ -n "$CLIP_SCHEME" ]] && to_phone "$CLIP_SCHEME"
echo "Your iPhone ($device): $SCHEME${CLIP_SCHEME:+ and $CLIP_SCHEME} running $commit"
