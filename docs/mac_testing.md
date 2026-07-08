# Mac Testing And iPhone Deploy Loop

Use this checklist when you want the Mac/iPhone build to match the newest code pushed from Windows/Codex.

Current expected Mac repo path:

```bash
cd ~/Desktop/market_coverage
```

If the repo lives somewhere else on the Mac, use that folder instead.

## Quick Path

From Terminal on the Mac:

```bash
cd ~/Desktop/market_coverage
git status --short
git pull --ff-only
flutter pub get
flutter devices
flutter run --release
```

If Flutter shows more than one device, copy the iPhone device id from `flutter devices` and run:

```bash
flutter run --release -d YOUR_IPHONE_DEVICE_ID
```

## Scripted Path

The repo also includes a helper script:

```bash
cd ~/Desktop/market_coverage
chmod +x scripts/mac_deploy.sh
./scripts/mac_deploy.sh
```

With a specific iPhone device id:

```bash
./scripts/mac_deploy.sh YOUR_IPHONE_DEVICE_ID
```

For debug mode instead of release mode:

```bash
./scripts/mac_deploy.sh YOUR_IPHONE_DEVICE_ID --debug
```

The scripted path is preferred for device testing because it injects the exact
app version, build number, Git branch, Git commit, and build time into Settings.

## Confirm You Are Testing The Newest Build

Before launching, the script prints:

- the repo folder
- the current Git branch
- the latest commit hash before pull
- the latest commit hash after pull
- the build identity injected into the app

The commit after pull is the build you are testing. After the app opens, go to:

```text
Settings > Build Identity
```

Tap `Copy Build Info` and paste that into bug reports or fix confirmations.

If you run Flutter manually instead of through the script, Settings can show
`unknown` for the commit because no `--dart-define` values were passed. In that
case, use this terminal command to confirm the Mac is on the newest code:

```bash
git log -1 --oneline
```

If the app still looks old after pulling:

```bash
flutter clean
flutter pub get
flutter run --release
```

## Common Problems

If `git pull --ff-only` fails because the Mac has local changes:

```bash
git status --short
```

Do not overwrite local Mac changes unless you know what they are. Send the output back to Codex first.

If the iPhone does not show in `flutter devices`:

- unlock the iPhone
- keep it plugged in
- trust the Mac from the iPhone prompt
- open Xcode once if iOS signing/device trust needs refreshing
- run `flutter doctor`

If the build installs but crashes immediately, copy the terminal error and include:

```bash
git log -1 --oneline
flutter devices
```

That gives Codex the exact build and device context.

If the app opens, include the copied `Settings > Build Identity` text instead.
