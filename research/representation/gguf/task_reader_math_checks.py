"""Synthetic numerical checks only; no model, artifact, or holdout file access."""
import json
import unittest

import numpy as np

from task_reader_math import HIDDEN_WIDTH, RIDGE_STRENGTHS, fit_ridge_reader


class TaskReaderMathChecks(unittest.TestCase):
    def fixture(self):
        rows, labels, groups = [], [], []
        for group in range(4):
            for label in (-1, 1):
                row = np.zeros(HIDDEN_WIDTH)
                row[0] = label
                row[group + 1] = 8 + group
                rows.append(row); labels.append(label); groups.append("group-" + str(group))
        calibration = np.zeros((4, HIDDEN_WIDTH))
        calibration[:, 0] = [-2, 2, -1, 1]
        return np.array(rows), np.array(labels), groups, calibration, np.array([-1, 1, -1, 1])

    def testFiniteUnitFitAndDeterministicStrongestTie(self):
        x, y, groups, calibration, labels = self.fixture()
        result = fit_ridge_reader(x, y, groups, calibration, labels)
        self.assertEqual(result.selected_strength, 10)
        self.assertEqual([x["strength"] for x in result.cv_summary], list(RIDGE_STRENGTHS))
        self.assertTrue(all(x["misclassified"] == 0 for x in result.cv_summary))
        self.assertAlmostEqual(float(np.linalg.norm(result.direction)), 1)
        np.testing.assert_allclose(result.center, x.mean(axis=0))
        self.assertGreater(result.calibration_separation, 0)
        self.assertAlmostEqual(result.score_offset, 0)
        self.assertAlmostEqual(result.score_scale, np.std(result.calibration_scores))
        centered = x - x.mean(axis=0)
        self.assertAlmostEqual(result.selected_alpha, 10 * np.trace(centered @ centered.T) / len(x))
        self.assertFalse(result.direction.flags.writeable)
        self.assertFalse(result.center.flags.writeable)
        self.assertFalse(result.calibration_scores.flags.writeable)
        json.dumps(result.cv_summary, allow_nan=False)
        order = [5, 3, 7, 0, 6, 2, 1, 4]
        shuffled = fit_ridge_reader(x[order], y[order], [groups[i] for i in order], calibration, labels)
        np.testing.assert_array_equal(shuffled.direction, result.direction)
        np.testing.assert_array_equal(shuffled.center, result.center)
        self.assertEqual(shuffled.cv_summary, result.cv_summary)

    def testWholePairFoldsCannotLearnTheHeldGroupsUniqueAxis(self):
        x, y, groups, calibration, labels = self.fixture()
        x[:] = 0
        for i, label in enumerate(y):
            x[i, i // 2] = label
        result = fit_ridge_reader(x, y, groups, calibration, labels)
        # Each pair is perfectly separable in-sample but its axis is absent from
        # the other groups. Leaving one row, instead of a pair, would leak it.
        for candidate in result.cv_summary:
            self.assertEqual(candidate["misclassified"], 8)
            self.assertEqual(len(candidate["folds"]), 4)
            for fold in candidate["folds"]:
                self.assertEqual(fold["trainingGroupCount"], 3)
                self.assertEqual(fold["heldLabels"], [-1, 1])
                self.assertEqual(fold["heldScores"], [0, 0])
                self.assertEqual(fold["misclassified"], 2)

    def testCalibrationCannotChangeDirectionOrSelectARegularizerAndOverlapIsRetained(self):
        x, y, groups, calibration, labels = self.fixture()
        first = fit_ridge_reader(x, y, groups, calibration, labels)
        reversed_calibration = -calibration
        second = fit_ridge_reader(x, y, groups, reversed_calibration, labels)
        np.testing.assert_array_equal(first.direction, second.direction)
        np.testing.assert_array_equal(first.center, second.center)
        self.assertEqual(first.cv_summary, second.cv_summary)
        self.assertEqual(first.selected_strength, second.selected_strength)
        self.assertLess(second.calibration_separation, 0)
        self.assertTrue(np.isfinite(second.calibration_scores).all())
        constant = fit_ridge_reader(x, y, groups, np.zeros_like(calibration), labels)
        self.assertEqual(constant.score_scale, 0)
        self.assertEqual(constant.calibration_separation, 0)
        self.assertTrue(np.isfinite(constant.calibration_scores).all())

    def testRejectsNonfiniteWrongShapesUnpairedGroupsAndAbsentCalibrationClass(self):
        x, y, groups, calibration, labels = self.fixture()
        for value in (np.nan, np.inf, -np.inf):
            bad = x.copy(); bad[0, 0] = value
            with self.assertRaises(ValueError): fit_ridge_reader(bad, y, groups, calibration, labels)
            bad_cal = calibration.copy(); bad_cal[0, 0] = value
            with self.assertRaises(ValueError): fit_ridge_reader(x, y, groups, bad_cal, labels)
        invalid = [
            (x[:, :-1], y, groups, calibration, labels),
            (x, y, ["all-one-group"] * len(groups), calibration, labels),
            (x, y, groups[:-1], calibration, labels),
            (x, np.ones_like(y), groups, calibration, labels),
            (x, y, groups, calibration, np.ones_like(labels)),
            (x, y == 1, groups, calibration, labels),
            (np.zeros_like(x), y, groups, calibration, labels),
        ]
        wrong_pair = y.copy(); wrong_pair[0] = 1
        invalid.append((x, wrong_pair, groups, calibration, labels))
        for args in invalid:
            with self.assertRaises(ValueError): fit_ridge_reader(*args)


if __name__ == "__main__":
    unittest.main()
