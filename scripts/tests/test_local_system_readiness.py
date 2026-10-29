"""Synthetic audit fixtures: no real installation, profiles or tools are used."""
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / 'script/check_local_system.py'
spec = importlib.util.spec_from_file_location('local_system_readiness', SOURCE)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class LocalSystemReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='archi-readiness-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / 'source'
        for name in audit.identity.REQUIRED:
            path = self.repo / name
            if name.endswith('.swift'):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('.package(path: "../shared/ARCHiSpatial")' if name.startswith('desktop/') else '// shared')
            else:
                path.mkdir(parents=True, exist_ok=True)
        (self.repo / 'script').mkdir()
        for name in ('build_and_run.sh', 'native_build_identity.py'):
            (self.repo / 'script' / name).write_text('# synthetic fixture')
        self.app = self.root / 'ARCHi.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/Resources').mkdir()
        (self.app / 'Contents/MacOS/ARCHiDesktop').write_bytes(b'fixture, never executed')
        (self.app / 'Contents/MacOS/ARCHiDesktop').chmod(0o755)
        self.info = self.app / 'Contents/Info.plist'
        self.info.write_bytes(plistlib.dumps({'CFBundleIdentifier': audit.APP_ID,
            'CFBundleExecutable': 'ARCHiDesktop', 'CFBundleShortVersionString': '0.7.0'}))
        snapshot = self.root / 'capture.json'
        audit.identity.capture(self.repo, snapshot, verification_requested=False, compiler='Swift fixture')
        self.receipt = audit.identity.seal(self.repo, snapshot, self.app,
                                         now=datetime(2026, 10, 29, tzinfo=timezone.utc))
        self.current = audit.identity.source_inputs(self.repo)

    def change_plist(self, **changes):
        value = plistlib.loads(self.info.read_bytes())
        value.update(changes)
        self.info.write_bytes(plistlib.dumps(value))

    def test_matching_receipt_has_bounded_identity_output(self):
        result = audit.installed_identity(self.app, self.current, '0.7.0')
        self.assertEqual(result['sourceContentID'], self.current['sourceContentID'])
        self.assertEqual(result['candidateID'], self.receipt['candidateID'])
        self.assertNotIn('sourceInputs', result)
        self.assertNotIn('preSignPayload', result)
        self.assertIn('not a final signed-artifact hash', result['scope'])

    def test_wrong_app_candidate_or_version_is_rejected(self):
        original = self.info.read_bytes()
        for change in ({'CFBundleIdentifier': 'other.app'}, {'ARCHiCandidateID': 'wrong'},
                       {'CFBundleVersion': '999.0.0'}, {'CFBundleShortVersionString': '0.1.0'},
                       {'ARCHiBuildContentID': '0' * 64}):
            with self.subTest(change=change):
                self.info.write_bytes(original)
                self.change_plist(**change)
                with self.assertRaises(ValueError):
                    audit.installed_identity(self.app, self.current, '0.7.0')

    def test_missing_receipt_and_tampered_source_inventory_are_rejected(self):
        receipt_path = self.app / audit.identity.RECEIPT
        original = receipt_path.read_bytes()
        receipt_path.unlink()
        with self.assertRaises((OSError, ValueError)):
            audit.installed_identity(self.app, self.current, '0.7.0')
        value = json.loads(original)
        value['sourceInputs']['files'].append({'path': 'unrecorded-input'})
        receipt_path.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, 'source identity is inconsistent'):
            audit.installed_identity(self.app, self.current, '0.7.0')

    def test_source_change_requires_new_candidate_and_unknown_source_fails(self):
        (self.repo / 'desktop/Sources/changed.swift').write_text('// later change')
        changed = audit.identity.source_inputs(self.repo)
        with self.assertRaisesRegex(ValueError, 'differs from current native source'):
            audit.installed_identity(self.app, changed, '0.7.0')
        with self.assertRaisesRegex(ValueError, 'could not be established'):
            audit.installed_identity(self.app, None, '0.7.0')

    def test_malformed_receipt_is_recorded_without_success(self):
        (self.app / audit.identity.RECEIPT).write_text('{"schema":"unsupported"}')
        checks = audit.Checks()
        checks.probe('identity', lambda: audit.installed_identity(self.app, self.current, '0.7.0'))
        self.assertEqual(checks.rows[0]['status'], 'failed')

    def test_wrong_platform_and_absent_tools_never_launch_commands(self):
        checks = audit.Checks()
        with patch.object(audit.platform, 'system', return_value='Linux'), \
             patch.object(audit.platform, 'machine', return_value='x86_64'), \
             patch.object(audit.shutil, 'which', return_value=None), \
             patch.object(audit, 'command') as command:
            self.assertFalse(audit.inspect_host(checks))
            command.assert_not_called()
        self.assertTrue(all(row['status'] == 'blocked' for row in checks.rows))

    def test_swift_62_minimum_and_malformed_macos_metadata(self):
        for version, expected in [('6.0', 'blocked'), ('6.1', 'blocked'), ('6.2', 'passed'), ('6.10', 'passed')]:
            with self.subTest(version=version), patch.object(audit.platform, 'system', return_value='Darwin'), \
                 patch.object(audit.platform, 'machine', return_value='arm64'), \
                 patch.object(audit.platform, 'mac_ver', return_value=('malformed', (), '')), \
                 patch.object(audit.shutil, 'which', side_effect=lambda name: '/tool/swift' if name == 'swift' else None), \
                 patch.object(audit, 'command', return_value='Apple Swift version ' + version):
                checks = audit.Checks()
                audit.inspect_host(checks)
                self.assertEqual(checks.rows[0]['status'], 'blocked')
                self.assertEqual(next(row for row in checks.rows if row['check'] == 'tool.swift')['status'], expected)

    def test_nonexecutable_native_and_unity_binaries_cannot_qualify(self):
        (self.app / 'Contents/MacOS/ARCHiDesktop').chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'not executable'):
            audit.installed_identity(self.app, self.current, '0.7.0')
        helper = self.app / 'Contents/Resources/UnityCompanion.app'
        (helper / 'Contents/MacOS').mkdir(parents=True)
        (helper / 'Contents/MacOS/player').write_bytes(b'not executable')
        capabilities = {key: 1 for key in ('ARCHiNativePresentationProtocol', 'ARCHiNativeArenaProtocol',
                        'ARCHiOrbPresentationVersion', 'ARCHiNativeStaffRecipeVersion',
                        'ARCHiSeedAppearanceVersion', 'ARCHiPersonalSeedVersion')}
        capabilities.update(CFBundleIdentifier='local.archi.unityport', CFBundleExecutable='player')
        (helper / 'Contents/Info.plist').write_bytes(plistlib.dumps(capabilities))
        checks = audit.Checks()
        audit.inspect_installed(checks, self.app, False)
        self.assertEqual(next(row for row in checks.rows if row['check'] == 'installed.unity-helper')['status'], 'failed')

    def test_embedded_file_pointer_is_not_a_semver_pin(self):
        (self.repo / 'package.json').write_text('{}')
        (self.repo / 'package-lock.json').write_text('{"packages":{"":{}}}')
        packages = self.repo / 'unity/ARCHi/Packages'
        (packages / 'com.example.fixture').mkdir(parents=True)
        (packages / 'manifest.json').write_text('{"dependencies":{}}')
        locked = {'version': 'file:com.example.fixture', 'source': 'embedded', 'dependencies': {}}
        lockfile = packages / 'packages-lock.json'
        lockfile.write_text(json.dumps({'dependencies': {'com.example.fixture': locked}}))
        packagefile = packages / 'com.example.fixture/package.json'
        metadata = {'name': 'com.example.fixture', 'version': '10.0.0', 'dependencies': {}}
        packagefile.write_text(json.dumps(metadata))
        self.assertFalse(audit.dependencies(self.repo)['embeddedPackages'][0]['versionPinnedByLock'])
        metadata['dependencies'] = {'unrecorded': '1.0.0'}
        packagefile.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, 'dependency map mismatch'):
            audit.dependencies(self.repo)
        locked['version'] = '11.0.0'
        lockfile.write_text(json.dumps({'dependencies': {'com.example.fixture': locked}}))
        with self.assertRaisesRegex(ValueError, 'version mismatch'):
            audit.dependencies(self.repo)

    def test_editor_metadata_is_independent_of_mac_player_module(self):
        version = self.repo / 'unity/ARCHi/ProjectSettings/ProjectVersion.txt'
        version.parent.mkdir(parents=True)
        version.write_text('m_EditorVersion: 6000.5.4f1\n')
        editor = self.root / 'Unity.app/Contents/MacOS/Unity'
        editor.parent.mkdir(parents=True)
        editor.write_text('fixture never executed')
        editor.chmod(0o755)
        (editor.parent.parent / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '6000.5.4f1'}))
        self.assertFalse((editor.parent.parent / 'PlaybackEngines/MacStandaloneSupport').exists())
        self.assertEqual(audit.editor_metadata(self.repo, editor)['version'], '6000.5.4f1')

    def test_nested_dependency_shapes_fail_as_rows_without_aborting_diagnostics(self):
        fixtures = {'package.json': {}, 'package-lock.json': {'packages': {'': {}}},
                    'unity/ARCHi/Packages/manifest.json': {'dependencies': {}},
                    'unity/ARCHi/Packages/packages-lock.json': {'dependencies': {}}}
        for relative, value in fixtures.items():
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value))
        broken = [('package.json', {'dependencies': []}), ('package-lock.json', {'packages': []}),
                  ('package-lock.json', {'packages': {'': []}}),
                  ('unity/ARCHi/Packages/manifest.json', {'dependencies': []}),
                  ('unity/ARCHi/Packages/packages-lock.json', {'dependencies': []}),
                  ('unity/ARCHi/Packages/packages-lock.json', {'dependencies': {'package': []}})]
        for relative, value in broken:
            with self.subTest(relative=relative, value=value):
                path = self.repo / relative
                path.write_text(json.dumps(value))
                checks = audit.Checks()
                checks.probe('dependencies', lambda: audit.dependencies(self.repo))
                checks.add('later', 'unverified', 'Diagnostic sequence continued')
                self.assertEqual([row['status'] for row in checks.rows], ['failed', 'unverified'])
                path.write_text(json.dumps(fixtures[relative]))

    def test_package_paths_cannot_read_foreign_metadata(self):
        packages = self.repo / 'unity/ARCHi/Packages'
        packages.mkdir(parents=True)
        outside = self.root / 'outside-source'
        outside.mkdir()
        foreign = outside / 'package.json'
        foreign.write_text(json.dumps({'name': str(outside), 'version': '10.0.0', 'dependencies': {}}))
        for kind, name in [('unity', str(outside)), ('npm', str(outside)), ('unity', '../outside'), ('npm', '@scope/../../outside')]:
            with self.subTest(kind=kind, name=name):
                npm = {'dependencies': {name: '10.0.0'}} if kind == 'npm' else {}
                (self.repo / 'package.json').write_text(json.dumps(npm))
                (self.repo / 'package-lock.json').write_text(json.dumps({'packages': {'': npm}}))
                (packages / 'manifest.json').write_text('{"dependencies":{}}')
                resolved = {name: {'version': 'file:' + name, 'source': 'embedded', 'dependencies': {}}} if kind == 'unity' else {}
                (packages / 'packages-lock.json').write_text(json.dumps({'dependencies': resolved}))
                with patch.object(audit, 'read', wraps=audit.read) as reader:
                    checks = audit.Checks()
                    checks.probe('dependencies', lambda: audit.dependencies(self.repo))
                self.assertEqual(checks.rows[0]['status'], 'failed')
                self.assertIn('Invalid package name', checks.rows[0]['detail'])
                self.assertFalse(any(Path(call.args[0]) == foreign for call in reader.call_args_list))
        audit.package_name('@noble/hashes', npm=True)

    def test_native_art_filename_cannot_escape_its_resource_root(self):
        native = self.repo / 'desktop/Sources/ARCHiDesktop'
        native.mkdir()
        (native / 'CompanionVisualTreatment.swift').write_text('static let filename = "/outside/portrait"\nstatic let digest = "' + 'a' * 64 + '"\n')
        with patch.object(audit.art, 'verify_loader'), patch.object(audit, 'hash_file', return_value='fixture') as hashed:
            checks = audit.Checks()
            audit.inspect_resources(checks, self.repo, self.app)
        contract = next(row for row in checks.rows if row['check'] == 'resource.contract')
        self.assertEqual(contract['status'], 'failed')
        self.assertIn('basename', contract['detail'])
        self.assertFalse(any(str(call.args[0]).startswith('/outside/') for call in hashed.call_args_list))

    def test_optional_reactor_absence_does_not_create_required_failure(self):
        checks = audit.Checks()
        with patch.object(audit, 'command') as command:
            audit.inspect_installed(checks, self.app, False)
            command.assert_not_called()
        reactor = next(row for row in checks.rows if row['check'] == 'optional.reactor')
        self.assertEqual(reactor['status'], 'passed')
        self.assertFalse(reactor['required'])
        self.change_plist(ARCHiReactorPython=str(self.app / 'Contents/Resources/ReactorRuntime/bin/python3'))
        checks = audit.Checks()
        audit.inspect_installed(checks, self.app, False)
        reactor = next(row for row in checks.rows if row['check'] == 'optional.reactor')
        self.assertNotEqual(reactor['status'], 'passed')
        self.assertFalse(reactor['required'])

    def test_report_exclusive_creation_and_private_mode(self):
        destination = self.root / 'report.json'
        audit.write_report(destination, {'status': 'blocked'}, self.repo)
        self.assertEqual(json.loads(destination.read_text()), {'status': 'blocked'})
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(FileExistsError):
            audit.write_report(destination, {'status': 'ready'}, self.repo)
        self.assertEqual(json.loads(destination.read_text())['status'], 'blocked')

    def test_report_refuses_source_app_and_symlink_destinations(self):
        directory = self.root / 'linked'
        directory.symlink_to(self.root, target_is_directory=True)
        dangling = self.root / 'dangling.json'
        dangling.symlink_to(self.root / 'missing.json')
        for destination in (self.repo / 'report.json', self.app / 'report.json',
                            directory / 'report.json', dangling, self.repo / '../report.json'):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                audit.write_report(destination, {}, self.repo)
        self.assertFalse((self.root / 'missing.json').exists())
        self.assertFalse((self.root / 'report.json').exists())

    def test_unverified_runtime_keeps_even_synthetic_static_success_nonready(self):
        (self.repo / 'package.json').write_text('{"version":"0.7.0"}')
        source = self.repo / 'desktop/Sources/ARCHiDesktop'
        source.mkdir()
        for name in audit.COMPONENTS:
            (source / name).write_text('// fixture')
        with patch.object(audit, 'inspect_host', return_value=True), \
             patch.object(audit, 'editor_metadata', return_value='fixture'), \
             patch.object(audit, 'dependencies', return_value='fixture'), \
             patch.object(audit, 'installed_identity', return_value='fixture'), \
             patch.object(audit, 'inspect_resources'), patch.object(audit, 'inspect_installed'):
            result = audit.audit(self.repo, self.app, self.root / 'Unity')
        self.assertEqual(result['status'], 'blocked')
        self.assertFalse(result['fullyInstalledVerified'])
        runtime = [row for row in result['checks'] if row['status'] == 'unverified']
        self.assertEqual(len(runtime), 5)
        self.assertNotIn('files', result['checks'][2].get('detail', {}))


if __name__ == '__main__':
    unittest.main()
