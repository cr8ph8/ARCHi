using System;
using System.Collections.Generic;

namespace ARCHi.Port
{
    /// <summary>Captured only after ArenaRehearsal resolves an explicit solo input.</summary>
    public readonly struct ArenaPracticeAction
    {
        public readonly string ActionID, BoutID;
        public readonly ArenaMove Move, RivalMove;
        public readonly ArenaField Field;
        public readonly int Round, IntegrityBefore, IntegrityAfter, RivalIntegrityBefore, RivalIntegrityAfter;
        public readonly int SparkBefore, SparkAfter, RivalSparkBefore, RivalSparkAfter, DamageDealt, DamageTaken, Absorbed;
        public readonly bool Complete;
        public readonly string Winner;

        public ArenaPracticeAction(string boutID, ArenaRehearsal bout, int round, int integrity, int rivalIntegrity, int spark, int rivalSpark)
        {
            if (bout == null || !bout.UsesAutomaticOpponent || round < 1 || round > 20
                || bout.Round != round + 1 || bout.Actions.Count != round || !Guid.TryParse(boutID, out _))
                throw new ArgumentException("Only an actually resolved solo action can be observed.");
            ActionID = Guid.NewGuid().ToString(); BoutID = boutID;
            Move = bout.LastMove; RivalMove = bout.LastRivalMove; Field = bout.Field; Round = round;
            IntegrityBefore = integrity; IntegrityAfter = bout.Integrity;
            RivalIntegrityBefore = rivalIntegrity; RivalIntegrityAfter = bout.RivalIntegrity;
            SparkBefore = spark; SparkAfter = bout.Spark; RivalSparkBefore = rivalSpark; RivalSparkAfter = bout.RivalSpark;
            DamageDealt = bout.DamageDealt; DamageTaken = bout.DamageTaken; Absorbed = bout.Absorbed;
            Complete = bout.Complete; Winner = bout.Winner;
        }
    }

    [Serializable]
    public sealed class WorldActionOutcome
    {
        public long sequence, presentationRevision;
        public string actionID, boutID, action, rivalAction, field, winner;
        public double atUnix;
        public int round, integrityBefore, integrityAfter, rivalIntegrityBefore, rivalIntegrityAfter;
        public int sparkBefore, sparkAfter, rivalSparkBefore, rivalSparkAfter, damageDealt, damageTaken, absorbed;
        public bool complete;

        internal static WorldActionOutcome Capture(ArenaPracticeAction fact, long sequence, long revision, double now) =>
            new WorldActionOutcome {
                sequence = sequence, presentationRevision = revision, actionID = fact.ActionID, boutID = fact.BoutID,
                atUnix = now, action = fact.Move.ToString().ToLowerInvariant(), rivalAction = fact.RivalMove.ToString().ToLowerInvariant(),
                field = fact.Field.ToString().ToLowerInvariant(), round = fact.Round,
                integrityBefore = fact.IntegrityBefore, integrityAfter = fact.IntegrityAfter,
                rivalIntegrityBefore = fact.RivalIntegrityBefore, rivalIntegrityAfter = fact.RivalIntegrityAfter,
                sparkBefore = fact.SparkBefore, sparkAfter = fact.SparkAfter,
                rivalSparkBefore = fact.RivalSparkBefore, rivalSparkAfter = fact.RivalSparkAfter,
                damageDealt = fact.DamageDealt, damageTaken = fact.DamageTaken, absorbed = fact.Absorbed,
                complete = fact.Complete, winner = fact.Winner
            };
    }

    [Serializable]
    public sealed class WorldOutcomeSnapshot
    {
        public int schemaVersion = 1;
        public string sessionID, originDigest, sessionKind, currentArea, mode;
        public long revision, firstSequence, lastSequence;
        public double updatedAtUnix;
        public WorldActionOutcome[] outcomes;
    }

    /// <summary>One native process session, bounded facts only. No command reader or saved-state owner.</summary>
    public sealed class WorldOutcomeJournal
    {
        public const int MaximumOutcomes = 32, MaximumBytes = 32768;
        private readonly string session;
        private readonly Queue<WorldActionOutcome> outcomes = new Queue<WorldActionOutcome>();
        private long sequence;
        private long lastEventRevision;
        private double lastEventTime;
        public WorldOutcomeJournal(string sessionID)
        {
            if (!Guid.TryParse(sessionID, out _)) throw new ArgumentException("A native session UUID is required.");
            session = sessionID;
        }

        public bool Record(ArenaPracticeAction fact, NativePresentationSnapshot presentation, double now)
        {
            if (presentation == null || presentation.sessionID != session || !presentation.active || !presentation.visible
                || presentation.revision < 1 || presentation.revision < lastEventRevision || !Guid.TryParse(fact.ActionID, out _)
                || double.IsNaN(now) || double.IsInfinity(now) || now <= 0 || now < lastEventTime
                || now - presentation.updatedAtUnix > NativePresentationSnapshot.MaximumAge
                || presentation.updatedAtUnix - now > NativePresentationSnapshot.MaximumAge || sequence == long.MaxValue) return false;
            foreach (var retained in outcomes) if (retained.actionID == fact.ActionID) return false;
            outcomes.Enqueue(WorldActionOutcome.Capture(fact, ++sequence, presentation.revision, now));
            while (outcomes.Count > MaximumOutcomes) outcomes.Dequeue();
            lastEventTime = now;
            lastEventRevision = presentation.revision;
            return true;
        }

        public WorldOutcomeSnapshot Observe(NativePresentationSnapshot presentation, string area, string mode, double now)
        {
            if (presentation == null || presentation.sessionID != session) return null;
            return new WorldOutcomeSnapshot {
                sessionID = session, originDigest = presentation.originDigest, sessionKind = presentation.SessionKind,
                revision = presentation.revision, updatedAtUnix = now, currentArea = area, mode = mode,
                firstSequence = outcomes.Count == 0 ? 0 : outcomes.Peek().sequence, lastSequence = sequence,
                outcomes = outcomes.ToArray()
            };
        }
    }
}
