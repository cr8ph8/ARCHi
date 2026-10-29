#!/usr/bin/env python3
"""Read-only ARCHi source, prerequisite and installed-bundle inspection.

This never builds, installs, launches providers, reads defaults/bookmarks or
opens profiles/saves. JSON goes to stdout; a summary goes to stderr. A report
is written only with --report, exclusively, outside source and app bundles.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_build_identity as identity
import package_companion_supplement as art
import package_record_reader as record_reader
import verify_preserved_liminal_seed as seed

REPO = Path(__file__).resolve().parents[1]
EDITOR = Path('/Applications/Unity/Hub/Editor/6000.5.4f1/Unity.app/Contents/MacOS/Unity')
APP_ID = 'com.quotient.archi.desktop.review'
COMPONENTS = ('HamptonNumericalDynamics.swift', 'HamptonQ2EController.swift',
              'HamptonDocumentNumericalControl.swift', 'HamptonReadingNumericalControl.swift',
              'HamptonARC3NumericalControl.swift', 'HamptonArenaAdvice.swift',
              'ContextualMemoryInfluence.swift', 'MemoryInfluenceIntegration.swift',
              'UnityPresentationConnection.swift', 'OrbPresentation.swift')


class PrerequisiteUnavailable(Exception):
    pass


def read(path, limit=16 * 1024 * 1024):
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        raise FileNotFoundError(path.name)
    return art.read_regular(path, limit)


def json_read(path):
    value = json.loads(read(path))
    if not isinstance(value, dict):
        raise ValueError('Expected an object in ' + Path(path).name)
    return value


def plist_read(path):
    value = plistlib.loads(read(path))
    if not isinstance(value, dict):
        raise ValueError('Expected a property-list dictionary')
    return value


def require(condition, message):
    if not condition:
        raise ValueError(message)


def mapping(value, label):
    require(isinstance(value, dict), label + ' must be an object')
    return value


def package_name(value, *, npm=False):
    pattern = r'(?:@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*' if npm else r'[A-Za-z0-9][A-Za-z0-9._-]*'
    require(isinstance(value, str) and re.fullmatch(pattern, value), 'Invalid package name; path traversal is not allowed')


def command(args):
    # Capture no provider output or environment. Commands are fixed metadata
    # queries or codesign verification, never supplied executable arguments.
    result = subprocess.run(args, capture_output=True, text=True, timeout=20)
    require(result.returncode == 0, Path(args[0]).name + ' query failed')
    return (result.stdout or result.stderr).strip()[:400]


class Checks:
    def __init__(self):
        self.rows = []

    def add(self, name, status, detail, required=True):
        self.rows.append(dict(check=name, status=status, required=required, detail=detail))

    def probe(self, name, function, required=True):
        try:
            result = function()
            self.add(name, 'passed', result, required)
            return result
        except (FileNotFoundError, PrerequisiteUnavailable) as error:
            detail = str(error) if isinstance(error, PrerequisiteUnavailable) else 'Required file or executable is absent.'
            self.add(name, 'blocked', detail, required)
        except (OSError, ValueError, KeyError, TypeError, UnicodeError,
                plistlib.InvalidFileException, subprocess.SubprocessError) as error:
            self.add(name, 'failed', str(error)[:250], required)
        return None


def inspect_host(checks):
    mac = platform.system() == 'Darwin'
    version = str(platform.mac_ver()[0] or '') if mac else ''
    major = re.match(r'^([0-9]{1,3})(?:\.|$)', version)
    supported = mac and major is not None and int(major[1]) >= 14 and platform.machine() == 'arm64'
    checks.add('host', 'passed' if supported else 'blocked',
               {'system': platform.system(), 'architecture': platform.machine(),
                'macOSVersion': version, 'required': 'macOS 14+ on ARM64 for the current Unity build'})
    for name, args in [('swift', ['--version']), ('xcodebuild', ['-version']), ('xcrun', ['--show-sdk-version']),
                       ('node', ['--version']), ('npm', ['--version'])]:
        executable = shutil.which(name)
        if not executable or (name in ('swift', 'xcodebuild', 'xcrun') and not mac):
            checks.add('tool.' + name, 'blocked', 'Required target tool is unavailable.')
            continue
        def inspect(executable=executable, args=args, name=name):
            value = command([executable, *args])
            if name == 'swift':
                parsed = re.search(r'Swift version ([0-9]{1,3})\.([0-9]{1,3})', value)
                require(parsed, 'Swift version could not be determined')
                if tuple(map(int, parsed.groups())) < (6, 2):
                    raise PrerequisiteUnavailable('Swift 6.2+ is required by the current isolated conformances')
            if name == 'node':
                require(re.match(r'v24\.', value), 'The retained source checks require Node 24')
            return value
        checks.probe('tool.' + name, inspect)
    return mac


def editor_metadata(repo, editor):
    expected = re.search(r'^m_EditorVersion: (\S+)', read(repo / 'unity/ARCHi/ProjectSettings/ProjectVersion.txt').decode(), re.M)
    require(expected, 'Pinned Unity version is missing')
    if not editor.exists():
        raise FileNotFoundError('Pinned Unity executable is unavailable')
    require(editor.is_file() and os.access(editor, os.X_OK), 'Pinned Unity executable is not executable')
    info = plist_read(editor.parent.parent / 'Info.plist')
    require(expected[1] in (info.get('CFBundleVersion'), info.get('CFBundleShortVersionString')),
            'Installed Unity metadata differs from the project pin')
    return {'version': expected[1], 'editorStarted': False,
            'scope': 'Editor metadata only; graphics/import and the separate player module are unverified.'}


def dependencies(repo):
    package = json_read(repo / 'package.json')
    packages = mapping(json_read(repo / 'package-lock.json').get('packages'), 'npm lock packages')
    lock = mapping(packages.get(''), 'npm lock root')
    for group in ('dependencies', 'devDependencies'):
        requested = mapping(package.get(group, {}), 'Root package ' + group)
        resolved = mapping(lock.get(group, {}), 'Root lock ' + group)
        for name in {*requested, *resolved}:
            package_name(name, npm=True)
        require(requested == resolved, 'Root package/lock dependency mismatch')
    unity = repo / 'unity/ARCHi/Packages'
    requested = mapping(json_read(unity / 'manifest.json').get('dependencies'), 'Unity manifest dependencies')
    resolved = mapping(json_read(unity / 'packages-lock.json').get('dependencies'), 'Unity lock dependencies')
    for name in {*requested, *resolved}:
        package_name(name)
    for name, record in resolved.items():
        mapping(record, 'Unity lock record ' + name)
    for name, version in requested.items():
        require(resolved.get(name, {}).get('version') == version, 'Unity lock mismatch: ' + name)
    embedded = []
    for name, record in resolved.items():
        if record['source'] == 'embedded':
            metadata = json_read(unity / name / 'package.json')
            require(metadata.get('name') == name, 'Missing embedded package: ' + name)
            version = record['version']
            require(isinstance(version, str), 'Invalid embedded lock version: ' + name)
            require(isinstance(metadata.get('version'), str) and metadata['version'], 'Embedded package version absent: ' + name)
            if version.startswith('file:'):
                require(version == 'file:' + name, 'Unexpected embedded package path: ' + name)
                wanted = mapping(metadata.get('dependencies', {}), 'Embedded dependencies ' + name)
                locked = mapping(record.get('dependencies', {}), 'Embedded lock dependencies ' + name)
                require(wanted == locked, 'Embedded dependency map mismatch: ' + name)
            else:
                require(metadata['version'] == version, 'Embedded package version mismatch: ' + name)
            embedded.append({'name': name, 'version': metadata['version'], 'versionPinnedByLock': not version.startswith('file:')})
    missing = []
    for name, version in {**package.get('dependencies', {}), **package.get('devDependencies', {})}.items():
        metadata = repo / 'node_modules' / name / 'package.json'
        if not metadata.is_file() or json_read(metadata).get('version') != version:
            missing.append(name)
    require(not missing, 'Direct npm dependencies absent or mismatched: ' + ', '.join(missing))
    return {'scope': 'Root lock, installed direct npm metadata and Unity lock agree; Unity import was not run.', 'embeddedPackages': embedded}


def hash_file(path, expected):
    require(re.fullmatch('[0-9a-f]{64}', expected), 'Invalid source digest pin')
    require(hashlib.sha256(read(path, 128 * 1024 * 1024)).hexdigest() == expected,
            'Resource hash mismatch: ' + path.name)
    return 'Exact bytes match the existing source pin.'


def inspect_resources(checks, repo, app):
    native = repo / 'desktop/Sources/ARCHiDesktop'
    for label, root in [('source', native / 'Resources'), ('installed', app / 'Contents/Resources')]:
        checks.probe('record-reader.' + label,
                     lambda root=root: hash_file(root / 'RecordReader/reader.qualified.json', record_reader.EXPECTED))
        for relative in ('Branding/AppIcon.icns', 'ReactorBridge/worker.py', 'ARC3Bridge/archi_arc3_bridge.py'):
            present = (root / relative).is_file()
            checks.add('resource.' + label + '.' + relative, 'present' if present else 'blocked',
                       'Required packaged resource present; execution unverified.' if present else 'Required packaged resource absent.')
    pins = dict(seed.PNG_PINS)
    try:
        source = read(native / 'CompanionVisualTreatment.swift').decode()
        art.verify_loader(native / 'CompanionVisualTreatment.swift')
        values = dict(re.findall(r'static let (\w+) = "([^"\r\n]+)"', source))
        for key in ('', 'kinSeed', 'kinFirstLight'):
            filename = values[key + ('Filename' if key else 'filename')]
            require(filename not in ('', '.', '..') and Path(filename).name == filename and '\\' not in filename,
                    'Native art filename must be a basename')
            pins[filename + '.png'] = values[key + ('Digest' if key else 'digest')]
    except (OSError, ValueError, KeyError, UnicodeError) as error:
        checks.add('resource.contract', 'failed', str(error)[:250])
    for name, digest in pins.items():
        for label, root in [('source', native / 'Resources/CompanionArt'), ('installed', app / 'Contents/Resources/CompanionArt')]:
            checks.probe('art.' + label + '.' + name, lambda root=root, name=name, digest=digest: hash_file(root / name, digest))
    for name, (_, digest) in art.APPROVED.items():
        checks.probe('art.optional-installed.' + name,
                     lambda name=name, digest=digest: hash_file(app / 'Contents/Resources/CompanionArt' / name, digest), False)
    unity = repo / 'unity/ARCHi/Assets'
    checks.probe('unity.proto-image', lambda: hash_file(unity / 'Resources/Proto/proto-body.png', art.APPROVED['archi-proto-blender-v1.png'][1]))
    for relative in ('Resources/KIN/kin-arena-motion-v1.fbx', 'Resources/Proto/proto-character.fbx',
                     'ARCHi/Resources/Orb/OrbEnergy.shader', 'ARCHi/Resources/Orb/OrbParticles.shader',
                     'ARCHi/Resources/Orb/OrbRoomSurface.shader', 'Resources/KIN/ArenaBloom.shader'):
        present = (unity / relative).is_file() and (unity / (relative + '.meta')).is_file()
        checks.add('unity.asset.' + relative, 'present' if present else 'blocked',
                   'Asset and metadata present; import/geometry/shader correctness unverified.' if present else 'Required asset or metadata absent.')


def installed_identity(app, current, expected_version):
    info = plist_read(app / 'Contents/Info.plist')
    require(info.get('CFBundleIdentifier') == APP_ID and info.get('CFBundleExecutable') == 'ARCHiDesktop',
            'Installed native bundle identifier/executable does not match ARCHi')
    executable = app / 'Contents/MacOS/ARCHiDesktop'
    require(executable.is_file() and not executable.is_symlink() and os.access(executable, os.X_OK),
            'Native executable is absent, linked or not executable')
    require(info.get('CFBundleShortVersionString') == expected_version, 'Installed marketing version differs from source')
    value = json_read(app / identity.RECEIPT)
    require(value.get('schema') == identity.BUILD_SCHEMA, 'Missing or unsupported build identity schema')
    require(isinstance(value.get('candidateID'), str), 'Missing candidate identity')
    require(str(uuid.UUID(value['candidateID'])) == value['candidateID'], 'Invalid candidate identity')
    require(re.fullmatch(r'[1-9]\d{0,3}\.\d{1,2}\.\d{1,2}', value['bundleVersion']), 'Invalid bundle version')
    source = mapping(value.get('sourceInputs'), 'Receipt sourceInputs')
    require(source['schema'] == identity.SOURCE_SCHEMA, 'Unsupported source identity schema')
    require(isinstance(source.get('files'), list) and isinstance(source.get('absentOptionalInputs'), list), 'Invalid source inventory lists')
    require(isinstance(value.get('preSignPayload'), list), 'Invalid payload inventory list')
    mapping(value.get('buildOptions'), 'Receipt buildOptions')
    computed = identity.digest({key: source[key] for key in ('files', 'absentOptionalInputs')})
    require(computed == source['sourceContentID'] == value['sourceContentID'], 'Receipt source identity is inconsistent')
    require(identity.digest(value['preSignPayload']) == value['preSignPayloadID'], 'Receipt payload identity is inconsistent')
    require(identity.digest({key: value[key] for key in ('sourceContentID', 'preSignPayloadID', 'buildOptions', 'compilerVersion')}) == value['contentID'], 'Receipt content identity is inconsistent')
    for field, key in [('CFBundleVersion', 'bundleVersion'), ('ARCHiCandidateID', 'candidateID'),
                       ('ARCHiSourceContentID', 'sourceContentID'), ('ARCHiBuildContentID', 'contentID')]:
        require(info.get(field) == value[key], 'Plist/receipt mismatch: ' + field)
    require(current is not None, 'Current native source identity could not be established')
    require(current['sourceContentID'] == value['sourceContentID'], 'Installed app differs from current native source inputs (including packaging scripts)')
    return {'candidateID': value['candidateID'], 'bundleVersion': value['bundleVersion'],
            'sourceContentID': value['sourceContentID'], 'contentID': value['contentID'],
            'scope': 'Receipt coherence and source equality; pre-sign payload is not a final signed-artifact hash.'}


def inspect_installed(checks, app, mac):
    helper = app / 'Contents/Resources/UnityCompanion.app'
    def protocols():
        info = plist_read(helper / 'Contents/Info.plist')
        require(info.get('CFBundleIdentifier') == 'local.archi.unityport', 'Unexpected Unity helper identifier')
        for key in ('ARCHiNativePresentationProtocol', 'ARCHiNativeArenaProtocol', 'ARCHiOrbPresentationVersion',
                    'ARCHiNativeStaffRecipeVersion', 'ARCHiSeedAppearanceVersion', 'ARCHiPersonalSeedVersion'):
            require(type(info.get(key)) is int and info[key] == 1, 'Missing/incompatible helper capability: ' + key)
        executable = info.get('CFBundleExecutable', '')
        require(isinstance(executable, str) and executable and Path(executable).name == executable, 'Invalid Unity executable name')
        binary = helper / 'Contents/MacOS' / executable
        require(binary.is_file() and not binary.is_symlink() and os.access(binary, os.X_OK), 'Unity helper binary is absent, linked or not executable')
        return 'Required presentation, Arena, orb, staff and Seed markers present; source freshness/runtime unverified.'
    checks.probe('installed.unity-helper', protocols)
    for label, bundle in [('native', app), ('unity', helper)]:
        if mac and shutil.which('codesign') and bundle.is_dir():
            checks.probe('signature.' + label, lambda bundle=bundle: command(['codesign', '--verify', '--deep', '--strict', str(bundle)]) or 'Strict signature verification passed; no notarization or publisher-trust claim.')
        else:
            checks.add('signature.' + label, 'blocked', 'Requires the actual Mac bundle and codesign.')
    def reactor():
        info = plist_read(app / 'Contents/Info.plist')
        declared = info.get('ARCHiReactorPython')
        if not declared:
            return 'Optional Reactor runtime is not declared; not invoked.'
        expected = app / 'Contents/Resources/ReactorRuntime/bin/python3'
        require(declared == str(expected), 'Reactor declaration does not point inside the selected app')
        require(expected.is_file() and os.access(expected, os.X_OK), 'Optional declared Reactor executable is absent')
        return 'Declared bundled runtime executable present; dependencies and execution unverified.'
    checks.probe('optional.reactor', reactor, False)


def audit(repo, app, editor):
    checks = Checks()
    mac = inspect_host(checks)
    checks.probe('unity.editor', lambda: editor_metadata(repo, editor))
    module_present = (editor.parent.parent / 'PlaybackEngines/MacStandaloneSupport').is_dir()
    checks.add('unity.mac-player-module', 'present' if module_present else 'blocked',
               'Module directory present; target build unverified.' if module_present else
               'Mac Standalone module absent. Required for player build; procedural orb acceptance does not require this module.')
    checks.probe('dependencies', lambda: dependencies(repo))
    current = checks.probe('native.source-identity', lambda: identity.source_inputs(repo))
    # The full inventory stays local/in memory; the public report needs only its ID.
    if current:
        checks.rows[-1]['detail'] = {'sourceContentID': current['sourceContentID'], 'inputRecords': len(current['files'])}
    checks.probe('installed.native-identity', lambda: installed_identity(app, current, json_read(repo / 'package.json')['version']))
    inspect_resources(checks, repo, app)
    inspect_installed(checks, app, mac)
    for name in COMPONENTS:
        present = (repo / 'desktop/Sources/ARCHiDesktop' / name).is_file()
        checks.add('source.component.' + name, 'present' if present else 'blocked',
                   'Source presence only; no caller, compilation or execution claim.' if present else 'Expected source component absent.')
    for name, detail in [
        ('native.runtime', 'Native build, installed UI, permissions, model availability and stop/reopen require actual Mac acceptance; no provider was called.'),
        ('unity.runtime', 'Run script/run_orb_runtime_acceptance.sh on the pinned Editor; no Unity acceptance was run or imported by this audit.'),
        ('spatial.q2e', 'The reviewed orb has no Q2E target-intent/outcome adapter; source-file presence does not establish that integration.'),
        ('headset.runtime', 'Physical sensing, platform SDK, pairing/input, stereo and device performance require implementation and hardware acceptance.'),
        ('first-signal.selection', 'Selection/bookmark/save inspection is deliberately excluded; use the existing packaging safeguard during actual delivery.')]:
        checks.add(name, 'unverified', detail)
    failed = any(row['required'] and row['status'] == 'failed' for row in checks.rows)
    pending = any(row['required'] and row['status'] in ('blocked', 'unverified') for row in checks.rows)
    return {'schema': 'archi-local-system-readiness/v1', 'utc': datetime.now(timezone.utc).isoformat(),
            'status': 'failed' if failed else 'blocked' if pending else 'ready',
            'fullyInstalledVerified': False, 'checks': checks.rows,
            'limits': 'Read-only audit, not an install, release approval or runtime test. No defaults, bookmarks, profiles, saves or provider endpoints were accessed.'}


def write_report(path, report, repo):
    path = path.expanduser()
    require('..' not in path.parts, 'Report path must not contain parent traversal')
    path = Path(os.path.abspath(path))
    require(path != repo and repo not in path.parents, 'Write reports outside the source checkout')
    require(not any(part.lower().endswith('.app') for part in path.parts), 'Report cannot be inside an app bundle')
    for ancestor in [path, *path.parents]:
        require(not ancestor.is_symlink(), 'Report path must not contain symlinks')
    require(path.parent.is_dir(), 'Report parent must already exist')
    # Anchor every directory traversal with O_NOFOLLOW as well as checking
    # names above, so replacing an ancestor with a symlink cannot redirect it.
    parent_fd = os.open(path.anchor, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:-1]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
            os.close(parent_fd)
            parent_fd = next_fd
        fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)
    with os.fdopen(fd, 'w') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=REPO)
    parser.add_argument('--app', type=Path, default=Path('/Applications/ARCHi.app'))
    parser.add_argument('--editor', type=Path, default=EDITOR)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(argv)
    repo, app, editor = [path.expanduser().resolve() for path in (args.repo, args.app, args.editor)]
    report = audit(repo, app, editor)
    if args.report:
        try:
            write_report(args.report, report, repo)
        except (OSError, ValueError) as error:
            print('Report was not written: ' + str(error), file=sys.stderr)
            return 2
    print(json.dumps(report, indent=2))
    counts = {state: sum(row['status'] == state for row in report['checks'])
              for state in ('passed', 'present', 'blocked', 'failed', 'unverified')}
    print('ARCHi inspection: ' + report['status'] + ' · ' + ', '.join(f'{n} {k}' for k, n in counts.items())
          + '. Installed runtime remains unverified.', file=sys.stderr)
    return 0 if report['status'] == 'ready' else 1


if __name__ == '__main__':
    raise SystemExit(main())
