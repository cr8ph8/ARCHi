#!/usr/bin/env python3
"""Copy an explicitly qualified loose point package into an unsigned app stage.

No downloading, Houdini launch, qualification manufacture, or profile mutation.
The existing build_and_run.sh signs/installs this stage and owns rollback.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
from liminal_v008_validate import validate_package, read_json


def package(source, qualification, native_resources, unity_streaming_assets, *, allow_finish=False, allow_light=False):
    source = Path(source)
    qualification = Path(qualification)
    if qualification.is_symlink() or qualification.stat().st_size > 4096:
        raise ValueError("invalid qualification receipt")
    receipt = read_json(qualification)
    required = {"schemaVersion", "assetID", "manifestSHA256", "sourceCooked",
                "nativeEndpointsPassed", "unityEndpointsPassed", "installedWalkthroughPassed"}
    if set(receipt) != required or type(receipt["schemaVersion"]) is not int or receipt["schemaVersion"] != 1 or receipt["assetID"] != "liminal-v008":
        raise ValueError("wrong qualification schema")
    if any(receipt[key] is not True for key in ("sourceCooked", "nativeEndpointsPassed", "unityEndpointsPassed")):
        raise ValueError("source and both renderer endpoints must qualify before activation")
    if type(receipt["installedWalkthroughPassed"]) is not bool:
        raise ValueError("installed walkthrough status must be explicit")
    validation = {"allow_finish": allow_finish, "allow_light": allow_light}
    result = validate_package(source, **validation)
    if result["manifestSHA256"] != receipt["manifestSHA256"] or result["endpointImageStatus"] != "qualified":
        raise ValueError("qualification does not match the complete package and its endpoint images")
    targets = [Path(native_resources) / "LiminalV008", Path(unity_streaming_assets) / "LiminalV008"]
    for target in targets:
        if target.exists() or target.is_symlink():
            # A copied existing helper can retain its identical qualified data.
            existing = validate_package(target, **validation)
            if existing["manifestSHA256"] != result["manifestSHA256"]:
                raise ValueError("stage already contains a different asset; prepare a new matching helper")
    for target in targets:
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            if sys.platform == "darwin":
                # The validated package has no symlinks. APFS clones are
                # independent files; cp falls back to copies on other volumes.
                subprocess.run(["/bin/cp", "-cR", str(source), str(target)], check=True)
            else:
                shutil.copytree(source, target, symlinks=False)
        copied = validate_package(target, **validation)
        if copied["manifestSHA256"] != result["manifestSHA256"] or copied["endpointImageStatus"] != "qualified":
            raise ValueError("copy changed qualified package bytes")
    shutil.copyfile(qualification, Path(native_resources) / "LiminalV008-qualification.json")
    return {**result, "nativeDestination": str(targets[0]), "unityDestination": str(targets[1]),
            "installedWalkthroughPassed": receipt["installedWalkthroughPassed"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "qualification", "native_resources", "unity_streaming_assets"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--allow-finish", action="store_true", help="independently validate any pinned finish-v11 child")
    parser.add_argument("--allow-light", action="store_true", help="also validate any pinned light-v12 child; requires --allow-finish")
    args = parser.parse_args()
    print(json.dumps(package(**vars(args)), indent=2))


if __name__ == "__main__":
    main()
