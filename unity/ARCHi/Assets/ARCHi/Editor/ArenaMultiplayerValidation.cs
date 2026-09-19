using System;
using System.Collections.Generic;
using System.IO;
using ARCHi.Port;
using UnityEditor;
using UnityEngine;

/// <summary>Pure command/replay checks. This does not claim a network or two-device playtest.</summary>
public static class ArenaMultiplayerValidation
{
    [Serializable] private sealed class Receipt
    {
        public string schema = "archi-arena-multiplayer-preparation/v1";
        public string utc;
        public int assertions, echoBouts, pairedBouts, rounds;
        public bool passed;
        public string scope = "Local deterministic two-seat command admission and replay; no network transport or native evolution grants.";
    }

    [MenuItem("ARCHi/Arena/Validate Two Player Commands")]
    public static void Validate()
    {
        if (!Application.dataPath.EndsWith("/unity/ARCHi/Assets", StringComparison.Ordinal))
            throw new InvalidOperationException("Wrong Unity project.");
        var receipt = new Receipt { utc = DateTime.UtcNow.ToString("O") };
        CheckEchoParity(receipt);
        CheckAdmission(receipt);
        CheckPairedTrajectories(receipt);
        receipt.passed = true;
        var repository = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
        var output = Path.Combine(repository, "output/arena-multiplayer-2026-09-18");
        Directory.CreateDirectory(output);
        File.WriteAllText(Path.Combine(output, "command-validation.json"), JsonUtility.ToJson(receipt, true));
        Debug.Log($"ARCHI_ARENA_MULTIPLAYER_PASS {receipt.echoBouts} ECHO bouts / {receipt.pairedBouts} paired bouts / {receipt.rounds} paired rounds / {receipt.assertions} assertions");
    }

    private static void CheckEchoParity(Receipt receipt)
    {
        foreach (ArenaField field in Enum.GetValues(typeof(ArenaField)))
        for (uint seed = 1; seed <= 30; seed++)
        {
            uint random = seed;
            var echo = new ArenaRehearsal(field);
            var paired = new ArenaRehearsal(field);
            while (!echo.Complete)
            {
                var move = Choice(ref random, echo.Spark);
                var rival = echo.RivalChoice();
                Check(echo.Resolve(move, echo.Round) && paired.ResolvePair(move, rival, paired.Round), "ECHO and paired resolution accept identical moves", receipt);
                Check(new ArenaStateSnapshot(echo).Revision == new ArenaStateSnapshot(paired).Revision, "ECHO mechanics and paired state remain identical", receipt);
            }
            Check(echo.UsesAutomaticOpponent && !paired.UsesAutomaticOpponent, "opponent provenance remains distinct", receipt);
            Check(new ArenaLearningPreview().Review(echo), "legacy ECHO review preserved", receipt);
            Check(!new ArenaLearningPreview().Review(paired), "human pairs cannot become ECHO learning evidence", receipt);
            receipt.echoBouts++;
        }
    }

    private static void CheckAdmission(Receipt receipt)
    {
        var session = NewSession("admission", ArenaField.Guardian);
        var one = session.CreateCommand(ArenaSeat.One, ArenaMove.Signature);
        var two = session.CreateCommand(ArenaSeat.Two, ArenaMove.Signature);
        var original = session.Revision;
        Check(!session.Bout.Resolve(ArenaMove.Pulse, 1) && !session.Bout.ResolvePair(ArenaMove.Pulse, ArenaMove.Pulse, 1), "session commands cannot be bypassed through Bout", receipt);
        Reject(session, ArenaSeat.One, null, "missing command", receipt);
        Reject(session, ArenaSeat.One, two, "wrong authenticated seat", receipt);
        Reject(session, (ArenaSeat)99, one, "unknown authenticated seat", receipt);
        Reject(session, ArenaSeat.One, Copy(one, match: "other"), "wrong match", receipt);
        Reject(session, ArenaSeat.One, Copy(one, actor: "other"), "wrong actor", receipt);
        Reject(session, ArenaSeat.One, Copy(one, round: 2), "wrong round", receipt);
        Reject(session, ArenaSeat.One, Copy(one, revision: "wrong"), "wrong revision", receipt);
        Reject(session, ArenaSeat.One, Copy(one, move: (ArenaMove)99), "unknown move", receipt);
        var first = session.Submit(ArenaSeat.One, one);
        Check(first.Accepted && !first.Resolved && session.HasPending(ArenaSeat.One) && !session.HasPending(ArenaSeat.Two), "first move waits privately for second seat", receipt);
        Check(session.Revision == original && session.Bout.Round == 1 && session.History.Count == 0, "first move does not advance or debit Spark", receipt);
        Reject(session, ArenaSeat.One, one, "duplicate command", receipt);
        Reject(session, ArenaSeat.One, Copy(one, move: ArenaMove.Guard), "move replacement after locking", receipt);
        Reject(session, ArenaSeat.Two, Copy(two, revision: "wrong"), "invalid sibling preserves first command", receipt);
        var second = session.Submit(ArenaSeat.Two, two);
        Check(second.Accepted && second.Resolved && session.Bout.Round == 2 && session.History.Count == 1, "second accepted move resolves exactly once", receipt);
        // Scout hits for 6; Guardian's 7-point shield absorbs all of it. Exposure starts after this hit.
        Check(session.Bout.Integrity == 36 && session.Bout.RivalIntegrity == 31 && session.Bout.Exposed &&
            session.Bout.Absorbed == 6 && session.Bout.DamageTaken == 0 && session.Bout.DamageDealt == 5 &&
            session.Bout.Spark == 2 && session.Bout.RivalSpark == 2, "known simultaneous Guardian/Scout signature outcome", receipt);
        Check(!session.HasPending(ArenaSeat.One) && !session.HasPending(ArenaSeat.Two) && session.Revision != original, "resolution clears pending moves and advances revision", receipt);
        Check(session.History[0].One.Move == ArenaMove.Signature && session.History[0].Two.Move == ArenaMove.Signature, "record retains both player choices", receipt);
        Reject(session, ArenaSeat.One, one, "late duplicate from previous round", receipt);
        Reject(session, ArenaSeat.Two, Copy(two, round: 2), "correct round with stale revision", receipt);
        Pair(session, ArenaMove.Signature, ArenaMove.Signature, false, receipt);
        Pair(session, ArenaMove.Signature, ArenaMove.Signature, true, receipt);
        Check(session.Bout.Spark == 0 && session.Bout.RivalSpark == 0, "both players consume their own Spark", receipt);
        Reject(session, ArenaSeat.One, session.CreateCommand(ArenaSeat.One, ArenaMove.Signature), "seat one exhausted Spark", receipt);
        Reject(session, ArenaSeat.Two, session.CreateCommand(ArenaSeat.Two, ArenaMove.Signature), "seat two exhausted Spark", receipt);
        while (!session.Bout.Complete) Pair(session, ArenaMove.Guard, ArenaMove.Guard, false, receipt);
        Check(session.Bout.Round == 21, "round cap completes two human match", receipt);
        Reject(session, ArenaSeat.One, session.CreateCommand(ArenaSeat.One, ArenaMove.Pulse), "completed match", receipt);
        VerifyReplay(session, receipt);

        var records = new List<ArenaRoundRecord>(session.History);
        records[0] = new ArenaRoundRecord(Copy(records[0].One, move: ArenaMove.Pulse), records[0].Two, records[0].After);
        ArenaMultiplayerSession replay; string reason;
        Check(!ArenaMultiplayerSession.TryReplay(session.MatchId, session.Bout.Field, session.ActorOne, session.ActorTwo, records, out replay, out reason) && replay == null,
            "changed move cannot pass a recorded-state replay", receipt);
        records = new List<ArenaRoundRecord>(session.History);
        records[0] = new ArenaRoundRecord(records[0].One, records[0].Two, new ArenaStateSnapshot(new ArenaRehearsal(ArenaField.Guardian)));
        Check(!ArenaMultiplayerSession.TryReplay(session.MatchId, session.Bout.Field, session.ActorOne, session.ActorTwo, records, out replay, out reason), "invented result rejected by replay", receipt);
        Check(!ArenaMultiplayerSession.TryReplay("other", session.Bout.Field, session.ActorOne, session.ActorTwo, session.History, out replay, out reason), "cross-match replay rejected", receipt);
        Check(!ArenaMultiplayerSession.TryReplay(session.MatchId, ArenaField.Scout, session.ActorOne, session.ActorTwo, session.History, out replay, out reason), "changed starting field rejected", receipt);
        Check(!ArenaMultiplayerSession.TryReplay(session.MatchId, session.Bout.Field, session.ActorTwo, session.ActorOne, session.History, out replay, out reason), "swapped actors rejected", receipt);
        Check(!ArenaMultiplayerSession.TryReplay(session.MatchId, session.Bout.Field, session.ActorOne, session.ActorTwo, null, out replay, out reason), "missing replay rejected", receipt);
        records = new List<ArenaRoundRecord>(session.History); records.Add(session.History[0]);
        Check(!ArenaMultiplayerSession.TryReplay(session.MatchId, session.Bout.Field, session.ActorOne, session.ActorTwo, records, out replay, out reason), "oversized replay rejected", receipt);

        var draw = NewSession("draw", ArenaField.Guardian);
        while (!draw.Bout.Complete) Pair(draw, ArenaMove.Guard, ArenaMove.Guard, false, receipt);
        Check(draw.Bout.Winner == "draw" && draw.Bout.Integrity == 36 && draw.Bout.RivalIntegrity == 36, "twenty guarded rounds resolve to draw", receipt);
        VerifyReplay(draw, receipt);
    }

    private static void CheckPairedTrajectories(Receipt receipt)
    {
        for (uint seed = 1; seed <= 60; seed++)
        {
            uint random = seed;
            var session = NewSession("pair-" + seed, ArenaField.Guardian);
            var reversed = NewSession("mirror-" + seed, ArenaField.Scout);
            while (!session.Bout.Complete)
            {
                var one = Choice(ref random, session.Bout.Spark);
                var two = Choice(ref random, session.Bout.RivalSpark);
                Pair(session, one, two, seed % 2 == 0, receipt);
                Pair(reversed, two, one, seed % 2 != 0, receipt);
                Check(session.Bout.Integrity == reversed.Bout.RivalIntegrity && session.Bout.RivalIntegrity == reversed.Bout.Integrity &&
                    session.Bout.Spark == reversed.Bout.RivalSpark && session.Bout.RivalSpark == reversed.Bout.Spark &&
                    session.Bout.Exposed == reversed.Bout.RivalExposed && session.Bout.RivalExposed == reversed.Bout.Exposed,
                    "swapping seats and fields mirrors state despite submission order", receipt);
                Check(session.Bout.Complete == reversed.Bout.Complete, "mirrored match completion", receipt);
                receipt.rounds++;
            }
            var mirroredWinner = session.Bout.Winner == "one" ? "two" : session.Bout.Winner == "two" ? "one" : "draw";
            Check(reversed.Bout.Winner == mirroredWinner, "seat-neutral winner", receipt);
            VerifyReplay(session, receipt); VerifyReplay(reversed, receipt);
            receipt.pairedBouts += 2;
        }
    }

    private static ArenaMultiplayerSession NewSession(string id, ArenaField field) => new ArenaMultiplayerSession(id, field, "player-one", "player-two");
    private static ArenaMove Choice(ref uint seed, int spark)
    {
        seed = unchecked(seed * 1664525u + 1013904223u);
        var move = (ArenaMove)((seed >> 16) % 3);
        return move == ArenaMove.Signature && spark == 0 ? ArenaMove.Pulse : move;
    }
    private static ArenaPlayerCommand Copy(ArenaPlayerCommand source, string match = null, string actor = null, string revision = null, int? round = null, ArenaMove? move = null)
        => new ArenaPlayerCommand(match ?? source.MatchId, round ?? source.Round, revision ?? source.Revision, source.Seat, actor ?? source.ActorId, move ?? source.Move);
    private static void Reject(ArenaMultiplayerSession session, ArenaSeat seat, ArenaPlayerCommand command, string label, Receipt receipt)
    {
        var revision = session.Revision; int count = session.History.Count;
        bool one = session.HasPending(ArenaSeat.One), two = session.HasPending(ArenaSeat.Two);
        var result = session.Submit(seat, command);
        Check(!result.Accepted && !result.Resolved && !string.IsNullOrEmpty(result.Reason) && session.Revision == revision &&
            session.History.Count == count && session.HasPending(ArenaSeat.One) == one && session.HasPending(ArenaSeat.Two) == two,
            label + " rejected without changing state or pending commands", receipt);
    }
    private static void Pair(ArenaMultiplayerSession session, ArenaMove one, ArenaMove two, bool twoFirst, Receipt receipt)
    {
        var commandOne = session.CreateCommand(ArenaSeat.One, one);
        var commandTwo = session.CreateCommand(ArenaSeat.Two, two);
        var first = session.Submit(twoFirst ? ArenaSeat.Two : ArenaSeat.One, twoFirst ? commandTwo : commandOne);
        var second = session.Submit(twoFirst ? ArenaSeat.One : ArenaSeat.Two, twoFirst ? commandOne : commandTwo);
        Check(first.Accepted && !first.Resolved && second.Accepted && second.Resolved, "both seats resolve independently of submission order", receipt);
    }
    private static void VerifyReplay(ArenaMultiplayerSession session, Receipt receipt)
    {
        ArenaMultiplayerSession replay; string reason;
        Check(ArenaMultiplayerSession.TryReplay(session.MatchId, session.Bout.Field, session.ActorOne, session.ActorTwo, session.History, out replay, out reason) &&
            replay.Revision == session.Revision && replay.Bout.Winner == session.Bout.Winner && replay.History.Count == session.History.Count,
            "complete paired history reproduces every deterministic state", receipt);
        Check(!new ArenaLearningPreview().Review(session.Bout), "two-seat session is not ECHO-certified learning", receipt);
    }
    private static void Check(bool condition, string label, Receipt receipt)
    {
        if (!condition) throw new InvalidOperationException("Arena multiplayer check failed: " + label);
        receipt.assertions++;
    }
}
