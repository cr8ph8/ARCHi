#!/usr/bin/env node
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parsePlacementRecording, comparePlacementRecording } from '../prototypes/desktop-companion/placement-recording.mjs';

const sameFrame = (a, b) => !!a && !!b && ['x', 'y', 'width', 'height'].every((key) => a[key] === b[key]);
const terminalKinds = ['dismissed', 'expired', 'invalidated', 'moved', 'recording-stopped', 'stayed', 'unconfirmed'];
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
let reportPath;
try {
  assert.equal(process.argv.length, 3, 'Usage: node script/check_native_placement_fixtures.mjs OUTPUT_DIRECTORY');
  const directory = resolve(process.argv[2]);
  reportPath = resolve(directory, 'cross-runtime-report.json');
  const manifestBytes = readFileSync(resolve(directory, 'synthetic-fixture-manifest.json'));
  const manifest = JSON.parse(manifestBytes);
  assert.equal(manifest.schema, 'archi-cross-runtime-placement-fixtures/v1');
  assert.equal(manifest.evidenceKind, 'synthetic-test-inputs');
  assert.equal(manifest.actualUIObserved, false);
  assert.equal(manifest.actualMovementObserved, false);
  assert.equal(manifest.recordingFile, 'synthetic-native-recording.json');
  assert.ok(Number.isInteger(manifest.expectedRecordCount) && manifest.expectedRecordCount >= 20 && manifest.expectedRecordCount <= 80);
  assert.equal(manifest.cases.length, manifest.expectedRecordCount);
  const recordingBytes = readFileSync(resolve(directory, manifest.recordingFile));
  const recording = parsePlacementRecording(recordingBytes.toString('utf8'));
  const comparison = comparePlacementRecording(recording);
  assert.equal(recording.schema, manifest.recordingSchema);
  assert.equal(recording.plannerVersion, manifest.plannerVersion);
  assert.equal(recording.records.length, manifest.expectedRecordCount);
  assert.equal(recording.limitReached, false);
  const terminalCounts = Object.fromEntries(terminalKinds.map((kind) => [kind, 0]));
  const geometries = new Set();
  const categories = new Set();
  for (let index = 0; index < recording.records.length; index += 1) {
    const record = recording.records[index], fixture = manifest.cases[index], result = comparison.records[index];
    assert.equal(record.id.toLowerCase(), fixture.id.toLowerCase(), `Fixture ID ${index}`);
    assert.equal(record.outcome.kind, fixture.expectedOutcome, `${fixture.name}: terminal outcome`);
    assert.deepEqual(record.proposal.frame, fixture.expectedNormalizedFrame, `${fixture.name}: recorder changed native proposal`);
    assert.equal(record.proposal.staysPut, fixture.expectedStaysPut, `${fixture.name}: native stay marker`);
    assert.equal(result.matchesRecordedProposal, true, `${fixture.name}: Swift/JavaScript planner parity`);
    const reproduced = result.lanes['current-planner'].frame;
    assert.deepEqual(reproduced, fixture.expectedNormalizedFrame, `${fixture.name}: exact cross-runtime frame`);
    assert.equal(sameFrame(reproduced, record.scene.companionFrame), fixture.expectedStaysPut, `${fixture.name}: exact cross-runtime stay decision`);
    assert.equal(result.lanes['current-planner'].eligible, true, `${fixture.name}: reproduced candidate eligibility`);
    assert.equal(result.lanes['current-planner'].overlapWithTarget, false, `${fixture.name}: selected fragment overlap`);
    geometries.add(JSON.stringify(record.scene));
    categories.add(fixture.category);
    terminalCounts[record.outcome.kind] += 1;
  }
  assert.equal(geometries.size, recording.records.length, 'Fixtures must have distinct normalized geometry');
  assert.deepEqual([...categories].sort(), manifest.coverageCategories);
  assert.deepEqual(manifest.expectedOutcomeKinds, terminalKinds);
  assert.ok(terminalKinds.every((kind) => terminalCounts[kind] > 0), 'Every terminal kind must be exercised');
  assert.deepEqual(comparison.summary.parity, { compared: recording.records.length, matched: recording.records.length, mismatched: 0 });
  const report = {
    schema: 'archi-cross-runtime-placement-report/v1', status: 'passed', evidenceKind: 'synthetic-test-inputs',
    actualUIObserved: false, actualMovementObserved: false,
    scope: 'Production Swift planner and recorder versus the JavaScript parser and deterministic planner port. This establishes fixture parity, not actual desktop behavior, causal benefit, or performance superiority.',
    plannerVersion: recording.plannerVersion, comparisonVersion: comparison.comparisonVersion,
    recordingSha256: hash(recordingBytes), manifestSha256: hash(manifestBytes),
    recordCount: recording.records.length, uniqueGeometryCount: geometries.size,
    parity: comparison.summary.parity, terminalCounts, coverageCategories: [...categories].sort(),
    geometricLaneTotals: comparison.summary.lanes,
  };
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`PASS: ${report.recordCount}/${report.recordCount} synthetic Swift/JavaScript proposals match exactly; ${terminalKinds.length} terminal kinds. No actual UI observations.`);
  console.log(`Report: ${reportPath}`);
} catch (error) {
  if (reportPath) {
    writeFileSync(reportPath, `${JSON.stringify({ schema: 'archi-cross-runtime-placement-report/v1', status: 'failed',
      evidenceKind: 'synthetic-test-inputs', actualUIObserved: false, error: error.message }, null, 2)}\n`);
  }
  console.error(`FAIL: synthetic cross-runtime fixture check: ${error.message}`);
  process.exitCode = 1;
}
