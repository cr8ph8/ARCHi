using System;
using ARCHi.Port;
using UnityEngine;

namespace ARCHi.Port.Editor
{
    /// <summary>Focused domain contract checks. No scene, player, profile, service or model work.</summary>
    public static class WorldOutcomeValidation
    {
        public static void Validate()
        {
            int checks = 0;
            Action<bool, string> check = (passed, reason) => {
                if (!passed) throw new InvalidOperationException("World outcome contract: " + reason);
                checks++;
            };
            string session = Guid.NewGuid().ToString();
            var presentation = new NativePresentationSnapshot { sessionID = session, originDigest = new string('a', 64),
                sessionKind = "companion", revision = 7, active = true, visible = true, updatedAtUnix = 1000 };
            var journal = new WorldOutcomeJournal(session);
            var fresh = new ArenaRehearsal(ArenaField.Guardian);
            bool rejectedUnresolved = false;
            try { _ = new ArenaPracticeAction(Guid.NewGuid().ToString(), fresh, 0, 36, 36, 3, 3); }
            catch (ArgumentException) { rejectedUnresolved = true; }
            check(rejectedUnresolved, "Unresolved rehearsal cannot claim an action.");
            ArenaPracticeAction last = default;
            for (int i = 1; i <= 40; i++) {
                var bout = new ArenaRehearsal(ArenaField.Guardian);
                check(bout.Resolve(ArenaMove.Pulse, 1), "Actual rule resolution must precede observation.");
                last = new ArenaPracticeAction(Guid.NewGuid().ToString(), bout, 1, 36, 36, 3, 3);
                check(journal.Record(last, presentation, 1000), "Fresh solo facts must be recorded.");
            }
            check(!journal.Record(last, presentation, 1000), "A repeated source action ID must not duplicate an outcome.");
            var snapshot = journal.Observe(presentation, "arena", "solo", 1000);
            check(snapshot.outcomes.Length == 32 && snapshot.firstSequence == 9 && snapshot.lastSequence == 40,
                "Ring eviction must preserve session sequence and expose the eight missing outcomes.");
            check(snapshot.outcomes[31].actionID == last.ActionID && snapshot.outcomes[31].integrityAfter == last.IntegrityAfter,
                "Serialized facts must correspond to the resolved action.");
            check(System.Text.Encoding.UTF8.GetByteCount(JsonUtility.ToJson(snapshot)) <= WorldOutcomeJournal.MaximumBytes,
                "Full ring must fit its wire bound.");
            var paired = new ArenaRehearsal(ArenaField.Guardian);
            check(paired.ResolvePair(ArenaMove.Pulse, ArenaMove.Guard, 1), "Pair fixture resolves separately.");
            bool rejectedPair = false;
            try { _ = new ArenaPracticeAction(Guid.NewGuid().ToString(), paired, 1, 36, 36, 3, 3); }
            catch (ArgumentException) { rejectedPair = true; }
            check(rejectedPair, "Paired outcomes cannot claim solo scope.");
            var staleBout = new ArenaRehearsal(ArenaField.Guardian); staleBout.Resolve(ArenaMove.Guard, 1);
            var staleFact = new ArenaPracticeAction(Guid.NewGuid().ToString(), staleBout, 1, 36, 36, 3, 3);
            check(!journal.Record(staleFact, presentation, 1006), "Expired native presentation must not record an action.");
            presentation.active = false;
            check(!journal.Record(staleFact, presentation, 1000), "Retired session must not record an action.");
            Debug.Log("ARCHI_WORLD_OUTCOME_CONTRACT_PASSED " + checks);
        }
    }
}
