#!/usr/bin/env python3
"""Compile/run orb C# boundary, navigation and viewport checks with a test-only JSON adapter.

This does not compile Unity rendering APIs, shaders, or the native macOS target.
The direct SDK compiler invocation also works on hosts where dotnet CLI telemetry
cannot query /proc. No packages are downloaded.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotnet", default=shutil.which("dotnet"))
    args = parser.parse_args()
    if not args.dotnet:
        parser.error("An installed .NET 8 SDK is required (--dotnet /path/to/dotnet).")
    executable = Path(args.dotnet).resolve()
    runtime = executable.parent
    compilers = sorted(runtime.glob("sdk/8.*/Roslyn/bincore/csc.dll"))
    references = sorted(runtime.glob("packs/Microsoft.NETCore.App.Ref/8.*/ref/net8.0"))
    frameworks = sorted(runtime.glob("shared/Microsoft.NETCore.App/8.*"))
    if not compilers or not references or not frameworks:
        parser.error("The selected dotnet installation must include the .NET 8 SDK and runtime.")
    root = Path(__file__).resolve().parents[1]
    sources = ["unity/ARCHi/Assets/ARCHi/Runtime/OrbPresentation.cs",
               "unity/ARCHi/Assets/ARCHi/Runtime/OrbRoomNavigation.cs",
               "unity/ARCHi/Assets/ARCHi/Runtime/NativePresentationSnapshot.cs",
               "unity/ARCHi/Assets/ARCHi/Editor/OrbPresentationChecks.cs",
               "unity/ARCHi/Assets/ARCHi/Editor/OrbRoomNavigationChecks.cs", "scripts/orb-checks/ProtocolHarness.cs"]
    with tempfile.TemporaryDirectory(prefix="archi-orb-checks-") as folder:
        output = Path(folder) / "OrbChecks.dll"
        options = ["/nologo", "/target:exe", "/langversion:latest", "/warnaserror+", "/nowarn:0649,SYSLIB0050", "/out:" + str(output)]
        options += ["/reference:" + str(path) for path in references[-1].glob("*.dll")]
        options += [str(root / path) for path in sources]
        response = Path(folder) / "compile.rsp"
        response.write_text("\n".join('"' + option.replace('"', '\\"') + '"' for option in options))
        subprocess.run([str(executable), str(compilers[-1]), "@" + str(response)], check=True)
        output.with_suffix(".runtimeconfig.json").write_text(json.dumps({"runtimeOptions": {
            "tfm": "net8.0", "framework": {"name": "Microsoft.NETCore.App", "version": frameworks[-1].name}}}))
        subprocess.run([str(executable), str(output)], check=True)


if __name__ == "__main__":
    main()
