#!/usr/bin/env python3
"""Build and notarize this fork with the developer account signed into Xcode.

Run without arguments to archive, submit, wait, and package a universal release.
Use --action submit or --action export with --archive-path to resume an archive.
Requires Xcode, its Metal toolchain, initialized build dependencies, and both
Apple Development and Developer ID Application certificates in the keychain.
"""

import argparse
from collections import deque
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent


def run(command, log=None, env=None):
    print(f"Running {command[0]} {command[1]}", flush=True)
    if log is None:
        subprocess.run(command, cwd=ROOT, env=env, check=True)
        return
    print(f"Log: {log}", flush=True)
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, env=env,
                                stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        with log.open() as output:
            print("".join(deque(output, maxlen=30)), file=sys.stderr)
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")


def archive_app(archive):
    with (archive / "Info.plist").open("rb") as source:
        metadata = plistlib.load(source)
    properties = metadata.get("ApplicationProperties")
    if not properties:
        raise RuntimeError("Xcode produced a generic archive. Check SKIP_INSTALL and exported headers.")
    app = archive / "Products" / properties["ApplicationPath"]
    return app, properties


def build_archive(archive, output, team):
    if archive.exists():
        raise RuntimeError(f"Archive already exists: {archive}. Use a new path or resume with --action.")
    shutil.copyfile(ROOT / "plists/release-iTerm2.plist", ROOT / "plists/iTerm2.plist")
    shutil.copyfile(ROOT / "xcstrings/Localizable.xcstrings", ROOT / "sources/Localizable.xcstrings")
    # SYMROOT overrides break archive assembly. Let Xcode arrange build products
    # under DerivedData so it writes the archive metadata itself.
    run(["xcodebuild", "-project", "iTerm2.xcodeproj", "-scheme", "iTerm2",
         "-configuration", "Deployment", "-destination", "generic/platform=macOS",
         "-archivePath", str(archive), "-derivedDataPath", str(output / "DerivedData"),
         "-allowProvisioningUpdates", "-skipPackagePluginValidation",
         "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", f"DEVELOPMENT_TEAM={team}",
         "CODE_SIGN_STYLE=Automatic", "CODE_SIGN_IDENTITY=Apple Development",
         "PROVISIONING_PROFILE_SPECIFIER=", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
         "ENABLE_ADDRESS_SANITIZER=NO", "archive"], output / "archive.log")

    app, properties = archive_app(archive)
    identity = properties["SigningIdentity"]
    # Keep the entire archive development-signed. A Developer ID or ad-hoc
    # Sparkle helper makes Xcode infer manual signing and refuse App ID setup.
    environment = dict(os.environ, CODESIGN_IDENTITY=identity)
    run([str(ROOT / "tools/sign_sparkle_helpers.sh"),
         str(app / "Contents/Frameworks/Sparkle.framework")],
        output / "sparkle-signing.log", environment)
    run(["codesign", "--force", "--sign", identity, "--options", "runtime",
         "--timestamp", "--preserve-metadata=identifier,entitlements,requirements,flags",
         str(app)])
    run(["codesign", "--verify", "--deep", "--strict", str(app)])


def submit(archive, output, team):
    archive_app(archive)  # Fail before uploading if the archive is incomplete.
    options = output / "ExportOptions.plist"
    with options.open("wb") as destination:
        plistlib.dump({"method": "developer-id", "destination": "upload",
                      "signingStyle": "automatic", "teamID": team,
                      "manageAppVersionAndBuildNumber": False}, destination)
    run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
         "-exportOptionsPlist", str(options), "-allowProvisioningUpdates"],
        output / "notarization-upload.log")


def export_notarized(archive, output, timeout):
    app, _ = archive_app(archive)
    destination = output / "notarized"
    if destination.exists():
        raise RuntimeError(f"Export destination already exists: {destination}. Use a new --output-dir.")
    command = ["xcodebuild", "-exportNotarizedApp", "-archivePath", str(archive),
               "-exportPath", str(destination)]
    deadline = time.monotonic() + timeout
    log = output / "notarization-export.log"
    while True:
        with log.open("w") as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode == 0:
            break
        message = log.read_text()
        # Do not retry rejected submissions or authentication failures.
        if "is processing and not ready for distribution" not in message:
            raise RuntimeError(message)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("Apple is still processing. Resume with --action export and the same paths.")
        print("Apple is processing the submission; checking again in 30 seconds.", flush=True)
        time.sleep(min(30, remaining))

    app = destination / app.name
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    run(["xcrun", "stapler", "validate", str(app)])
    run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)])
    architectures = subprocess.check_output(
        ["lipo", "-archs", str(app / "Contents/MacOS/iTerm2")], text=True).split()
    if not {"arm64", "x86_64"}.issubset(architectures):
        raise RuntimeError(f"Expected a universal app; found architectures: {architectures}")
    with (app / "Contents/Info.plist").open("rb") as source:
        version = plistlib.load(source)["CFBundleShortVersionString"]
    package = output / f"iTerm2-{version}-universal-notarized.zip"
    if package.exists():
        raise RuntimeError(f"ZIP already exists: {package}")
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(package)])
    print(f"Notarized release: {package}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=["all", "archive", "submit", "export"], default="all")
    parser.add_argument("--team-id", default="L46X9FWR42")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/notarized-release")
    parser.add_argument("--archive-path", type=Path)
    parser.add_argument("--wait-timeout", type=int, default=1800, help="Notarization wait in seconds")
    args = parser.parse_args()
    if args.wait_timeout < 0:
        parser.error("--wait-timeout must be nonnegative")
    output = args.output_dir.resolve()
    archive = (args.archive_path or output / "iTerm2.xcarchive").resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive.parent.mkdir(parents=True, exist_ok=True)
    if args.action in ("all", "archive"):
        build_archive(archive, output, args.team_id)
    if args.action in ("all", "submit"):
        submit(archive, output, args.team_id)
    if args.action in ("all", "export"):
        export_notarized(archive, output, args.wait_timeout)


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
