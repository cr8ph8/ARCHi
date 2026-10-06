using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace ARCHi.Port
{
    public enum ArenaSeat { One, Two }

    /// <summary>A move proposal; the caller's authenticated seat is supplied separately at admission.</summary>
    public sealed class ArenaPlayerCommand
    {
        public string MatchId { get; }
        public int Round { get; }
        public string Revision { get; }
        public ArenaSeat Seat { get; }
        public string ActorId { get; }
        public ArenaMove Move { get; }
        public ArenaPlayerCommand(string matchId, int round, string revision, ArenaSeat seat, string actorId, ArenaMove move)
        {
            MatchId = matchId; Round = round; Revision = revision; Seat = seat; ActorId = actorId; Move = move;
        }
    }

    /// <summary>Immutable, deterministic result. No native identity, personal memory or evolution data.</summary>
    public sealed class ArenaStateSnapshot
    {
        public int Round { get; }
        public ArenaField Field { get; }
        public int Integrity { get; }
        public int RivalIntegrity { get; }
        public int Spark { get; }
        public int RivalSpark { get; }
        public bool Exposed { get; }
        public bool RivalExposed { get; }
        public string Winner { get; }
        public int GuardedRounds { get; }
        public int ScoutedRounds { get; }
        public int Absorbed { get; }
        public int DamageTaken { get; }
        public int DamageDealt { get; }
        public ArenaMove LastMove { get; }
        public ArenaMove LastRivalMove { get; }
        public string Revision { get; }

        public ArenaStateSnapshot(ArenaRehearsal bout)
        {
            if (bout == null) throw new ArgumentNullException(nameof(bout));
            Round = bout.Round; Field = bout.Field;
            Integrity = bout.Integrity; RivalIntegrity = bout.RivalIntegrity;
            Spark = bout.Spark; RivalSpark = bout.RivalSpark;
            Exposed = bout.Exposed; RivalExposed = bout.RivalExposed; Winner = bout.Winner;
            GuardedRounds = bout.GuardedRounds; ScoutedRounds = bout.ScoutedRounds;
            Absorbed = bout.Absorbed; DamageTaken = bout.DamageTaken; DamageDealt = bout.DamageDealt;
            LastMove = bout.LastMove; LastRivalMove = bout.LastRivalMove;
            var canonical = string.Format(CultureInfo.InvariantCulture,
                "archi-arena-pair/v1|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}",
                Round, (int)Field, Integrity, RivalIntegrity, Spark, RivalSpark, Exposed ? 1 : 0,
                RivalExposed ? 1 : 0, Winner, GuardedRounds, ScoutedRounds, Absorbed, DamageTaken,
                DamageDealt, (int)LastMove, (int)LastRivalMove);
            using (var hash = SHA256.Create())
                Revision = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-", "").ToLowerInvariant();
        }
    }

    public sealed class ArenaRoundRecord
    {
        public ArenaPlayerCommand One { get; }
        public ArenaPlayerCommand Two { get; }
        public ArenaStateSnapshot After { get; }
        public ArenaRoundRecord(ArenaPlayerCommand one, ArenaPlayerCommand two, ArenaStateSnapshot after)
        {
            One = one; Two = two; After = after;
        }
    }

    public sealed class ArenaCommandResult
    {
        public bool Accepted { get; }
        public bool Resolved { get; }
        public string Reason { get; }
        internal ArenaCommandResult(bool accepted, bool resolved, string reason)
        {
            Accepted = accepted; Resolved = resolved; Reason = reason;
        }
    }

    /// <summary>
    /// Disposable, local two-seat command authority. No sockets, remote authentication, persistence,
    /// rewards or native evolution grants. A future transport must bind its peer to authenticatedSeat;
    /// a seat claimed inside a packet is never sufficient. Presentation only reads Bout.
    /// </summary>
    public sealed class ArenaMultiplayerSession
    {
        private readonly object gate = new object();
        private readonly List<ArenaRoundRecord> history = new List<ArenaRoundRecord>();
        private readonly ReadOnlyCollection<ArenaRoundRecord> visibleHistory;
        private ArenaPlayerCommand pendingOne, pendingTwo;
        private ArenaStateSnapshot state;
        public string MatchId { get; }
        public string ActorOne { get; }
        public string ActorTwo { get; }
        public ArenaRehearsal Bout { get; }
        public string Revision { get { lock (gate) return state.Revision; } }
        public ArenaStateSnapshot State { get { lock (gate) return state; } }
        public IReadOnlyList<ArenaRoundRecord> History => visibleHistory;

        public ArenaMultiplayerSession(string matchId, ArenaField field, string actorOne, string actorTwo)
        {
            if (!ValidId(matchId) || !ValidId(actorOne) || !ValidId(actorTwo) || actorOne == actorTwo)
                throw new ArgumentException("A match and two distinct, non-empty actor IDs are required (maximum 128 characters).");
            MatchId = matchId; ActorOne = actorOne; ActorTwo = actorTwo;
            Bout = new ArenaRehearsal(field);
            Bout.ClaimCommands(gate);
            state = new ArenaStateSnapshot(Bout);
            visibleHistory = history.AsReadOnly();
        }

        public bool HasPending(ArenaSeat seat)
        {
            lock (gate) return seat == ArenaSeat.One ? pendingOne != null : seat == ArenaSeat.Two && pendingTwo != null;
        }

        public ArenaPlayerCommand CreateCommand(ArenaSeat seat, ArenaMove move)
        {
            if (!ValidSeat(seat)) throw new ArgumentOutOfRangeException(nameof(seat));
            lock (gate) return new ArenaPlayerCommand(MatchId, Bout.Round, state.Revision, seat,
                seat == ArenaSeat.One ? ActorOne : ActorTwo, move);
        }

        public ArenaCommandResult Submit(ArenaSeat authenticatedSeat, ArenaPlayerCommand command)
        {
            lock (gate)
            {
                var error = Validate(authenticatedSeat, command);
                if (error != null) return new ArenaCommandResult(false, false, error);
                if (command.Seat == ArenaSeat.One) pendingOne = command; else pendingTwo = command;
                if (pendingOne == null || pendingTwo == null)
                    return new ArenaCommandResult(true, false, "Move locked. Waiting for the other player.");

                // The bout is exclusively owned; neither presentation nor a second input path can advance it.
                if (!Bout.ResolveOwnedPair(gate, pendingOne.Move, pendingTwo.Move, Bout.Round))
                    throw new InvalidOperationException("Validated commands failed deterministic resolution.");
                state = new ArenaStateSnapshot(Bout);
                history.Add(new ArenaRoundRecord(pendingOne, pendingTwo, state));
                pendingOne = null; pendingTwo = null;
                return new ArenaCommandResult(true, true, Bout.Complete ? "Match complete." : "Both moves resolved.");
            }
        }

        private string Validate(ArenaSeat authenticatedSeat, ArenaPlayerCommand command)
        {
            if (command == null) return "Missing command.";
            if (!ValidSeat(authenticatedSeat) || !ValidSeat(command.Seat) || command.Seat != authenticatedSeat)
                return "This player does not own that seat.";
            if (command.MatchId != MatchId) return "Wrong match.";
            if (command.ActorId != (command.Seat == ArenaSeat.One ? ActorOne : ActorTwo)) return "Wrong actor.";
            if (Bout.Complete) return "The match is complete.";
            if (command.Round != Bout.Round || command.Revision != state.Revision) return "Stale round or revision.";
            if (!Enum.IsDefined(typeof(ArenaMove), command.Move)) return "Unknown move.";
            if (HasPending(command.Seat)) return "This player already locked a move for this round.";
            if (command.Move == ArenaMove.Signature && (command.Seat == ArenaSeat.One ? Bout.Spark : Bout.RivalSpark) == 0)
                return "No Spark remains for that move.";
            return null;
        }

        /// <summary>Recompute every pair; compare recorded states rather than accepting a claimed outcome.</summary>
        public static bool TryReplay(string matchId, ArenaField field, string actorOne, string actorTwo,
            IReadOnlyList<ArenaRoundRecord> rounds, out ArenaMultiplayerSession replay, out string reason)
        {
            replay = null; reason = "Invalid replay.";
            if (rounds == null || rounds.Count > 20) return false;
            ArenaMultiplayerSession candidate;
            try { candidate = new ArenaMultiplayerSession(matchId, field, actorOne, actorTwo); }
            catch (ArgumentException) { return false; }
            foreach (var round in rounds)
            {
                if (round == null || round.One == null || round.Two == null || round.After == null) return false;
                var one = candidate.Submit(ArenaSeat.One, round.One);
                var two = candidate.Submit(ArenaSeat.Two, round.Two);
                if (!one.Accepted || one.Resolved || !two.Accepted || !two.Resolved ||
                    candidate.Revision != round.After.Revision) return false;
            }
            replay = candidate; reason = "Both commands and every resulting state verified.";
            return true;
        }

        private static bool ValidSeat(ArenaSeat seat) => seat == ArenaSeat.One || seat == ArenaSeat.Two;
        private static bool ValidId(string value)
        {
            if (string.IsNullOrWhiteSpace(value) || value.Length > 128) return false;
            foreach (var character in value) if (char.IsControl(character)) return false;
            return true;
        }
    }
}
