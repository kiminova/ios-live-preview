---
name: ios-live-preview
description: Keep two iOS simulators (one in light mode, one in dark) and the developer's iPhone on the latest build of the app, refreshed after every change, so they can look at the work at any moment. Use at the start of a session in an iOS project and after every change you build, when the user wants to see the app on their simulators or phone, or asks to set up a live preview.
---

# iOS live preview

The developer wants to see your work at any moment, in three places, always on the latest build:

- **`<Name> Light`**: a simulator in light mode.
- **`<Name> Dark`**: a simulator in dark mode.
- **Their iPhone**: the app, and its App Clip if it has one.

`scripts/refresh.sh` in this skill's folder does all of it. Run it from the project's folder.

## First time in a project

The script reads `.ios-preview` in the project's folder. If there is none:

1. List the schemes: `xcodebuild -list` (add `-workspace` or `-project` if the folder has several).
2. Pick the app's scheme, and its App Clip's if there is one. If it's not obvious, ask the user which.
3. Write `.ios-preview`:

   ```bash
   SCHEME="MyApp"
   NAME="MyApp"                 # the simulators: "MyApp Light", "MyApp Dark"
   # CLIP_SCHEME="MyApp Clip"   # put on the phone after the app
   # LAUNCH_ARGS=(-demo YES)    # e.g. to run against made-up data
   # WORKSPACE="MyApp.xcworkspace"
   ```

4. Ask the user whether to commit it, so their team gets the same setup, or keep it to themselves (add it to `.gitignore`).

## Every session

1. **At the start**, before anything else, run `scripts/refresh.sh` (from this skill's folder, in the project's folder). It creates the two simulators if they're missing, boots them, builds the app from the working tree, and installs and launches it in both. Then it builds and installs the app, and the Clip, on the first iPhone paired with the Mac.
2. **After every change you build**, run it again. Tell the user which commit the devices run: the script's last lines say so.
3. **If a line starts with `NOTE phone:`**, the phone wasn't updated. Pass the note on as it is, and don't retry in a loop. The simulators are refreshed all the same.

## Rules

- Use these two simulators and no others. Don't create or boot another simulator for a test, a recording or a check. If another one is booted, shut it down (`xcrun simctl shutdown <udid>`). Never delete a simulator.
- **The simulator panel is the developer's view.** Claude Code's simulator panel holds both simulators side by side. Attaching, detaching, or taking a screenshot or tapping through the simulator tool with a device named can take one of them out of the panel or swap it. Don't attach or detach the panel unless the developer says a simulator is missing. Look at a simulator from the terminal instead: `xcrun simctl io <udid> screenshot <file>`, then read the file. Use the tool's taps and swipes only when a check needs them, and say so first.
- The App Clip goes on the phone after the app, every time, because installing the full app removes its Clip. The script does it in that order.
- Options: `--no-phone` (the simulators only), `--no-build` (reinstall the last simulator build, the phone skipped).

## If the phone isn't updated

- **"no iPhone paired":** the phone has never been paired with this Mac. Pair it once with a cable, with Developer Mode on (Settings › Privacy & Security). After that it updates over Wi-Fi.
- **The build failed:** usually signing. The user's Apple ID must be in the app's team in Xcode (Settings › Accounts). The log path is in the note.
- **Unreachable:** the phone is off the Mac's network, or asleep for a long time. A cable always works.
