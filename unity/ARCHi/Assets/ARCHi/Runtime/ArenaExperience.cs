using System;
using System.Collections.Generic;
using System.Globalization;

namespace ARCHi.Port
{
    /// <summary>Facts reconstructed from a completed bout, never a saved developmental grant.</summary>
    public sealed class ArenaExperience
    {
        public const int RulesVersion = 1;
        public ArenaField Field { get; private set; }
        public int Rounds { get; private set; }
        public int ProtectedRounds { get; private set; }
        public int ExposureApplications { get; private set; }
        public int IntegrityRemaining { get; private set; }
        public string Outcome { get; private set; }
        public double? EarlyDiversity { get; private set; }
        public double? LateDiversity { get; private set; }
        public string Direction => !EarlyDiversity.HasValue ? "unmeasured" :
            Math.Abs(LateDiversity.Value - EarlyDiversity.Value) < .000001 ? "steady" :
            LateDiversity.Value > EarlyDiversity.Value ? "diversifying" : "consolidating";
        public string Effect => "unassessed";
        public bool CanGrantEvolution => false;
        public string Candidate => Field == ArenaField.Guardian && ProtectedRounds > 0
            ? "Protection timing · skill candidate" : Field == ArenaField.Scout && ExposureApplications > 0
            ? "Recognizing openings · skill candidate" : "Read the encounter · experience only";
        public string Explanation => $"{Candidate}. {ProtectedRounds} protected rounds; {ExposureApplications} exposure applications; {IntegrityRemaining}/36 integrity remaining. " +
            (EarlyDiversity.HasValue ? "Action diversity " + EarlyDiversity.Value.ToString("F2", CultureInfo.InvariantCulture) + " → " + LateDiversity.Value.ToString("F2", CultureInfo.InvariantCulture) + " bits (" + Direction + "). " : "Too few actions to compare diversity. ") +
            "Helpful or harmful effect: unassessed. A fresh situation and a reviewed lesson are still needed; no mastery or body change is granted.";

        public static ArenaExperience FromCompleted(ArenaRehearsal bout)
        {
            if (bout == null || !bout.Complete || !bout.UsesAutomaticOpponent) return null;
            var replay = new ArenaRehearsal(bout.Field);
            foreach (var move in bout.Actions) if (!replay.Resolve(move, replay.Round)) return null;
            if (!replay.Complete || replay.Winner != bout.Winner || replay.Integrity != bout.Integrity ||
                replay.RivalIntegrity != bout.RivalIntegrity || replay.Round != bout.Round || replay.Spark != bout.Spark ||
                replay.RivalSpark != bout.RivalSpark || replay.GuardedRounds != bout.GuardedRounds || replay.ScoutedRounds != bout.ScoutedRounds) return null;
            var result = new ArenaExperience { Field = replay.Field, Rounds = replay.Actions.Count,
                ProtectedRounds = replay.GuardedRounds, ExposureApplications = replay.ScoutedRounds,
                IntegrityRemaining = replay.Integrity, Outcome = replay.Winner };
            // Equal-size windows, fixed Pulse/Guard/Signature bins. If odd, omit the central action.
            // Spark availability and changing opposition are confounders; direction is not competence.
            var count = replay.Actions.Count / 2;
            if (count >= 2) {
                result.EarlyDiversity = Diversity(replay.Actions, 0, count);
                result.LateDiversity = Diversity(replay.Actions, replay.Actions.Count - count, count);
            }
            return result;
        }

        private static double Diversity(IReadOnlyList<ArenaMove> actions, int start, int count)
        {
            var bins = new int[3];
            for (int i = start; i < start + count; i++) bins[(int)actions[i]]++;
            double entropy = 0;
            foreach (var value in bins) if (value > 0) { double p = value / (double)count; entropy -= p * Math.Log(p, 2); }
            return entropy;
        }
    }
}
