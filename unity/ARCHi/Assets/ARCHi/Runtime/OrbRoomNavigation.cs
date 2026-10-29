using System;
using System.Collections.Generic;

namespace ARCHi.Port
{
    public readonly struct OrbVector3
    {
        public readonly double X, Y, Z;
        public OrbVector3(double x, double y, double z) { X = x; Y = y; Z = z; }
        public bool IsFinite => Finite(X) && Finite(Y) && Finite(Z);
        public double Length => Math.Sqrt(X * X + Y * Y + Z * Z);
        public static OrbVector3 Zero => new OrbVector3(0, 0, 0);
        public static OrbVector3 operator +(OrbVector3 a, OrbVector3 b) => new OrbVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
        public static OrbVector3 operator -(OrbVector3 a, OrbVector3 b) => new OrbVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
        public static OrbVector3 operator *(OrbVector3 a, double b) => new OrbVector3(a.X * b, a.Y * b, a.Z * b);
        public static double Distance(OrbVector3 a, OrbVector3 b) => (a - b).Length;
        internal static bool Finite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);
    }

    public readonly struct OrbBounds3
    {
        public readonly OrbVector3 Min, Max;
        public OrbBounds3(OrbVector3 min, OrbVector3 max) { Min = min; Max = max; }
        public OrbVector3 Center => (Min + Max) * .5;
        public OrbVector3 Size => Max - Min;
        public bool IsValid => Min.IsFinite && Max.IsFinite && Min.X < Max.X && Min.Y < Max.Y && Min.Z < Max.Z;
        public bool Contains(OrbVector3 point) => point.IsFinite
            && point.X >= Min.X && point.X <= Max.X && point.Y >= Min.Y && point.Y <= Max.Y
            && point.Z >= Min.Z && point.Z <= Max.Z;
        internal OrbBounds3 Expanded(double amount)
        {
            var margin = new OrbVector3(amount, amount, amount);
            return new OrbBounds3(Min - margin, Max + margin);
        }
    }

    /// <summary>One explicitly registered room object, not an inferred recognition result or memory.</summary>
    public sealed class OrbRoomTarget
    {
        public string Id { get; }
        public string Label { get; }
        public OrbBounds3 Bounds { get; }
        public OrbVector3 Approach { get; }
        public long Generation { get; }
        public OrbRoomTarget(string id, string label, OrbBounds3 bounds, OrbVector3 approach, long generation = 1)
        { Id = id; Label = label; Bounds = bounds; Approach = approach; Generation = generation; }
    }

    public readonly struct OrbTargetRef
    {
        public readonly string SpaceID, TargetID;
        public readonly long SceneRevision, Generation;
        public OrbTargetRef(string spaceID, long sceneRevision, string targetID, long generation)
        { SpaceID = spaceID; SceneRevision = sceneRevision; TargetID = targetID; Generation = generation; }
    }

    public static class OrbRoomViewport
    {
        /// <summary>Map a top-left UI point through a centered ScaleToFit image to Unity's bottom-left viewport.</summary>
        public static bool TryNormalize(double x, double y, double width, double height, double textureWidth, double textureHeight,
            out double u, out double v)
        {
            u = v = 0;
            if (!OrbVector3.Finite(x) || !OrbVector3.Finite(y) || !OrbVector3.Finite(width) || !OrbVector3.Finite(height)
                || !OrbVector3.Finite(textureWidth) || !OrbVector3.Finite(textureHeight)
                || width <= 0 || height <= 0 || textureWidth <= 0 || textureHeight <= 0) return false;
            double scale = Math.Min(width / textureWidth, height / textureHeight);
            double imageWidth = textureWidth * scale, imageHeight = textureHeight * scale;
            if (!OrbVector3.Finite(imageWidth) || !OrbVector3.Finite(imageHeight) || imageWidth <= 0 || imageHeight <= 0) return false;
            double left = (width - imageWidth) * .5, top = (height - imageHeight) * .5;
            if (x < left || x > left + imageWidth || y < top || y > top + imageHeight) return false;
            u = (x - left) / imageWidth; v = 1 - (y - top) / imageHeight;
            return true;
        }
    }

    /// <summary>
    /// Transient, room-local movement for the presentation body. No Unity Physics scene,
    /// native journal, perception, or transport state is owned here. Bounds are conservative:
    /// inflated boxes can refuse a tight corner but cannot authorize motion through furniture.
    /// </summary>
    public sealed class OrbRoomNavigation
    {
        public const double FixedStep = 1.0 / 120.0;
        public const int MaximumCatchUpSteps = 8;
        private const int MaximumGridCells = 16000;
        private const double GridSpacing = .35, ArrivalTolerance = .00001, DwellSeconds = 1.6;
        private readonly double speed;
        private OrbBounds3 centerBounds;
        private OrbBounds3[] obstacles = Array.Empty<OrbBounds3>();
        private IReadOnlyList<OrbRoomTarget> targets = Array.AsReadOnly(Array.Empty<OrbRoomTarget>());
        private readonly Dictionary<string, OrbRoomTarget> targetsByID = new Dictionary<string, OrbRoomTarget>(StringComparer.Ordinal);
        private readonly Dictionary<string, long> spaceRevisions = new Dictionary<string, long>(StringComparer.Ordinal);
        private readonly List<OrbVector3> route = new List<OrbVector3>();
        private int routeIndex, exploreIndex = -1, explorationRemaining, explorationVisits;
        private double accumulator, currentSpeed, dwell;
        private bool hasScene, completingExploration;
        public double Radius { get; }
        public OrbVector3 Center { get; private set; }
        public OrbVector3 Home { get; private set; }
        public OrbRoomTarget SelectedTarget { get; private set; }
        public IReadOnlyList<OrbRoomTarget> Targets => targets;
        public string State { get; private set; } = "Room unavailable";
        public bool IsMoving => routeIndex < route.Count;
        public bool IsExploring { get; private set; }
        public long SceneRevision { get; private set; }
        public string SpaceID { get; private set; }

        public OrbRoomNavigation(double radius = .46, double speed = 1.25)
        {
            if (!OrbVector3.Finite(radius) || radius <= 0)
                throw new ArgumentOutOfRangeException(nameof(radius), "A finite positive body radius is required.");
            if (!OrbVector3.Finite(speed) || speed <= 0)
                throw new ArgumentOutOfRangeException(nameof(speed), "A finite positive speed is required.");
            Radius = radius; this.speed = speed;
        }

        /// <summary>Replace one complete authored scene. Invalid replacements leave the current scene untouched.</summary>
        public void SetScene(string spaceID, long revision, OrbBounds3 bounds, IReadOnlyList<OrbBounds3> sceneObstacles,
            IReadOnlyList<OrbRoomTarget> sceneTargets, OrbVector3 home)
        {
            if (string.IsNullOrWhiteSpace(spaceID) || spaceID.Length > 128 || revision <= 0)
                throw new ArgumentException("A space and an increasing positive scene revision are required.");
            if (spaceRevisions.TryGetValue(spaceID, out var previousRevision) ? revision <= previousRevision : spaceRevisions.Count >= 64)
                throw new ArgumentException("Retired space revisions cannot be reused; one instance supports at most 64 spaces.");
            if (!Bounded(bounds) || sceneObstacles == null || sceneObstacles.Count > 128
                || sceneTargets == null || sceneTargets.Count > 64)
                throw new ArgumentException("Supply bounded room geometry and at most 128 obstacles and 64 objects.");
            var allowed = bounds.Expanded(-Radius);
            if (!allowed.IsValid) throw new ArgumentException("The room must contain the complete orb body.");
            var nextObstacles = new OrbBounds3[sceneObstacles.Count];
            for (int i = 0; i < nextObstacles.Length; i++)
            {
                if (!Bounded(sceneObstacles[i])) throw new ArgumentException("Obstacle bounds must be finite and nondegenerate.");
                nextObstacles[i] = sceneObstacles[i].Expanded(Radius);
            }
            if (!PositionFree(home, allowed, nextObstacles)) throw new ArgumentException("Home must have full body clearance.");
            var nextTargets = new OrbRoomTarget[sceneTargets.Count];
            var ids = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < nextTargets.Length; i++)
            {
                var target = sceneTargets[i];
                if (target == null || string.IsNullOrWhiteSpace(target.Id) || target.Id.Length > 128
                    || string.IsNullOrWhiteSpace(target.Label) || target.Label.Length > 128 || target.Generation <= 0
                    || !ids.Add(target.Id) || !Bounded(target.Bounds) || !PositionFree(target.Approach, allowed, nextObstacles))
                    throw new ArgumentException("Objects need unique IDs, finite bounds and a collision-free approach point.");
                // OrbRoomTarget and its value fields are immutable; only the collection needs a copy.
                nextTargets[i] = target;
            }

            centerBounds = allowed; obstacles = nextObstacles; targets = Array.AsReadOnly(nextTargets);
            targetsByID.Clear();
            foreach (var target in nextTargets) targetsByID.Add(target.Id, target);
            // Retain a bounded replay fence across A -> B -> A transitions; never revive an old target token.
            spaceRevisions[spaceID] = revision;
            SpaceID = spaceID; SceneRevision = revision; Home = Center = home; hasScene = true;
            Cancel(); State = "At home";
        }

        public OrbTargetRef GetTargetRef(string id)
        {
            if (id == null || !targetsByID.TryGetValue(id, out var target)) throw new ArgumentException("Unknown room object.", nameof(id));
            return new OrbTargetRef(SpaceID, SceneRevision, target.Id, target.Generation);
        }

        /// <summary>A stale or forged object reference cannot redirect an existing movement.</summary>
        public bool SelectTarget(OrbTargetRef reference)
        {
            if (!hasScene || !string.Equals(reference.SpaceID, SpaceID, StringComparison.Ordinal)
                || reference.SceneRevision != SceneRevision || reference.TargetID == null
                || !targetsByID.TryGetValue(reference.TargetID, out var target) || reference.Generation != target.Generation) return false;
            IsExploring = completingExploration = false; SelectedTarget = target;
            bool reachable = StartRoute(target.Approach);
            State = reachable ? IsMoving ? "Moving to " + target.Label : "Inspecting " + target.Label
                : "No clear path to " + target.Label;
            return reachable;
        }

        public bool Explore()
        {
            if (!hasScene || targets.Count == 0) return false;
            exploreIndex = -1;
            if (SelectedTarget != null)
                for (int i = 0; i < targets.Count; i++) if (targets[i].Id == SelectedTarget.Id) { exploreIndex = i; break; }
            IsExploring = true; completingExploration = false; explorationRemaining = targets.Count; explorationVisits = 0;
            return NextExplorationTarget();
        }

        public bool ReturnHome()
        {
            if (!hasScene) return false;
            IsExploring = completingExploration = false; SelectedTarget = null;
            bool reachable = StartRoute(Home);
            State = reachable ? IsMoving ? "Returning home" : "At home" : "No clear path home";
            return reachable;
        }

        public void Cancel()
        {
            route.Clear(); routeIndex = 0; currentSpeed = accumulator = dwell = 0;
            IsExploring = completingExploration = false; SelectedTarget = null; exploreIndex = -1;
            explorationRemaining = explorationVisits = 0;
            State = hasScene ? "Here with you" : "Room unavailable";
        }

        public bool IsPositionFree(OrbVector3 position) => hasScene && PositionFree(position, centerBounds, obstacles);

        public bool IsSegmentFree(OrbVector3 from, OrbVector3 to)
        {
            // The allowed room volume is convex, so safe endpoints keep the whole segment inside it.
            if (!IsPositionFree(from) || !IsPositionFree(to)) return false;
            foreach (var obstacle in obstacles) if (Intersects(from, to, obstacle)) return false;
            return true;
        }

        public void Tick(double deltaTime, bool paused = false)
        {
            if (paused) { accumulator = currentSpeed = 0; return; }
            if (!hasScene || !OrbVector3.Finite(deltaTime) || deltaTime <= 0) return;
            // Resume never consumes a backlog from a hidden view, blocked frame or paused host.
            accumulator = Math.Min(accumulator + Math.Min(deltaTime, .1), FixedStep * MaximumCatchUpSteps);
            int count = 0;
            while (accumulator + 1e-12 >= FixedStep && count++ < MaximumCatchUpSteps)
            { accumulator = Math.Max(0, accumulator - FixedStep); Step(); }
        }

        private void Step()
        {
            if (!IsMoving)
            {
                if (IsExploring && (dwell += FixedStep) >= DwellSeconds) NextExplorationTarget();
                return;
            }
            double remaining = OrbVector3.Distance(Center, route[routeIndex]);
            for (int i = routeIndex + 1; i < route.Count; i++) remaining += OrbVector3.Distance(route[i - 1], route[i]);
            const double acceleration = 2.5;
            double desired = Math.Min(speed, Math.Sqrt(2 * acceleration * remaining));
            currentSpeed += Math.Max(-acceleration * FixedStep, Math.Min(acceleration * FixedStep, desired - currentSpeed));
            double travel = currentSpeed * FixedStep;
            while (IsMoving && travel > 0)
            {
                var goal = route[routeIndex];
                var delta = goal - Center; double distance = delta.Length;
                double advance = Math.Min(travel, distance);
                bool arrived = advance >= distance || distance <= ArrivalTolerance;
                var next = distance <= ArrivalTolerance ? goal : Center + delta * (advance / distance);
                if (!IsSegmentFree(Center, next))
                { route.Clear(); routeIndex = 0; currentSpeed = 0; IsExploring = false; State = "Path blocked"; return; }
                Center = next; travel -= advance;
                if (arrived) routeIndex++;
                else break;
            }
            if (!IsMoving)
            {
                currentSpeed = 0; dwell = 0;
                State = completingExploration ? "Exploration complete" : SelectedTarget == null ? "At home" : "Inspecting " + SelectedTarget.Label;
            }
        }

        private bool NextExplorationTarget()
        {
            while (explorationRemaining > 0)
            {
                explorationRemaining--;
                exploreIndex = (exploreIndex + 1) % targets.Count;
                var target = targets[exploreIndex];
                if (!StartRoute(target.Approach)) continue;
                SelectedTarget = target; dwell = 0; explorationVisits++;
                State = IsMoving ? "Exploring: " + target.Label : "Inspecting " + target.Label;
                return true;
            }
            IsExploring = false; SelectedTarget = null; completingExploration = true;
            bool homeReachable = StartRoute(Home);
            State = !homeReachable ? "No clear path home" : IsMoving ? "Returning home"
                : explorationVisits > 0 ? "Exploration complete" : "No accessible room objects";
            return homeReachable && explorationVisits > 0;
        }

        private bool StartRoute(OrbVector3 destination)
        {
            route.Clear(); routeIndex = 0; currentSpeed = accumulator = dwell = 0;
            if (!IsPositionFree(destination)) return false;
            if (OrbVector3.Distance(Center, destination) <= ArrivalTolerance) return true;
            if (IsSegmentFree(Center, destination)) { route.Add(destination); return true; }
            return PlanRoute(destination);
        }

        private bool PlanRoute(OrbVector3 destination)
        {
            var grid = new Grid(centerBounds);
            var costs = new double[grid.Count];
            var parents = new int[grid.Count];
            var free = new bool[grid.Count];
            var closed = new bool[grid.Count];
            var open = new MinHeap();
            for (int i = 0; i < grid.Count; i++)
            {
                costs[i] = double.PositiveInfinity; parents[i] = -1;
                var point = grid.Point(i); free[i] = IsPositionFree(point);
                // Connect the actual start, not a rounded cell that could be across a wall.
                if (!free[i] || !IsSegmentFree(Center, point)) continue;
                costs[i] = OrbVector3.Distance(Center, point);
                open.Push(i, costs[i] + OrbVector3.Distance(point, destination));
            }
            while (open.Count > 0)
            {
                int current = open.Pop();
                if (closed[current]) continue;
                closed[current] = true;
                var point = grid.Point(current);
                if (IsSegmentFree(point, destination))
                {
                    var backwards = new List<OrbVector3> { destination };
                    for (int step = current; step >= 0; step = parents[step]) backwards.Add(grid.Point(step));
                    backwards.Reverse();
                    var from = Center;
                    for (int i = 0; i < backwards.Count;)
                    {
                        int farthest = backwards.Count - 1;
                        while (farthest > i && !IsSegmentFree(from, backwards[farthest])) farthest--;
                        if (!IsSegmentFree(from, backwards[farthest])) { route.Clear(); return false; }
                        route.Add(backwards[farthest]); from = backwards[farthest]; i = farthest + 1;
                    }
                    return true;
                }
                for (int direction = 0; direction < 6; direction++)
                {
                    int neighbor = grid.Neighbor(current, direction);
                    if (neighbor < 0 || closed[neighbor] || !free[neighbor]) continue;
                    var next = grid.Point(neighbor);
                    double cost = costs[current] + OrbVector3.Distance(point, next);
                    if (cost >= costs[neighbor] || !IsSegmentFree(point, next)) continue;
                    costs[neighbor] = cost; parents[neighbor] = current;
                    open.Push(neighbor, cost + OrbVector3.Distance(next, destination));
                }
            }
            return false;
        }

        private static bool Bounded(OrbBounds3 bounds) => bounds.IsValid
            && Math.Abs(bounds.Min.X) <= 10000 && Math.Abs(bounds.Min.Y) <= 10000 && Math.Abs(bounds.Min.Z) <= 10000
            && Math.Abs(bounds.Max.X) <= 10000 && Math.Abs(bounds.Max.Y) <= 10000 && Math.Abs(bounds.Max.Z) <= 10000;
        private static bool PositionFree(OrbVector3 point, OrbBounds3 allowed, OrbBounds3[] blocked)
        {
            if (!allowed.Contains(point)) return false;
            foreach (var obstacle in blocked) if (obstacle.Contains(point)) return false;
            return true;
        }
        private static bool Intersects(OrbVector3 start, OrbVector3 end, OrbBounds3 bounds)
        {
            double enter = 0, leave = 1;
            return Slab(start.X, end.X - start.X, bounds.Min.X, bounds.Max.X, ref enter, ref leave)
                && Slab(start.Y, end.Y - start.Y, bounds.Min.Y, bounds.Max.Y, ref enter, ref leave)
                && Slab(start.Z, end.Z - start.Z, bounds.Min.Z, bounds.Max.Z, ref enter, ref leave);
        }
        private static bool Slab(double start, double delta, double min, double max, ref double enter, ref double leave)
        {
            if (delta == 0) return start >= min && start <= max;
            double first = (min - start) / delta, last = (max - start) / delta;
            if (first > last) { double swap = first; first = last; last = swap; }
            enter = Math.Max(enter, first); leave = Math.Min(leave, last);
            return enter <= leave;
        }

        private sealed class Grid
        {
            private readonly OrbBounds3 bounds;
            private readonly int xCount, yCount, zCount;
            public int Count => xCount * yCount * zCount;
            public Grid(OrbBounds3 bounds)
            {
                this.bounds = bounds;
                double spacing = GridSpacing;
                do {
                    xCount = Math.Max(2, (int)Math.Ceiling(bounds.Size.X / spacing) + 1);
                    yCount = Math.Max(2, (int)Math.Ceiling(bounds.Size.Y / spacing) + 1);
                    zCount = Math.Max(2, (int)Math.Ceiling(bounds.Size.Z / spacing) + 1);
                    spacing *= 1.25;
                } while ((long)xCount * yCount * zCount > MaximumGridCells);
            }
            public OrbVector3 Point(int index)
            {
                int x = index % xCount, y = index / xCount % yCount, z = index / (xCount * yCount);
                return new OrbVector3(bounds.Min.X + bounds.Size.X * x / (xCount - 1),
                    bounds.Min.Y + bounds.Size.Y * y / (yCount - 1), bounds.Min.Z + bounds.Size.Z * z / (zCount - 1));
            }
            public int Neighbor(int index, int direction)
            {
                int x = index % xCount, y = index / xCount % yCount, z = index / (xCount * yCount);
                switch (direction)
                {
                    case 0: return x > 0 ? index - 1 : -1;
                    case 1: return x + 1 < xCount ? index + 1 : -1;
                    case 2: return y > 0 ? index - xCount : -1;
                    case 3: return y + 1 < yCount ? index + xCount : -1;
                    case 4: return z > 0 ? index - xCount * yCount : -1;
                    default: return z + 1 < zCount ? index + xCount * yCount : -1;
                }
            }
        }

        private sealed class MinHeap
        {
            private readonly List<Entry> entries = new List<Entry>();
            private readonly struct Entry
            {
                public readonly int Index;
                public readonly double Priority;
                public Entry(int index, double priority) { Index = index; Priority = priority; }
            }
            public int Count => entries.Count;
            private static bool Before(Entry a, Entry b) => a.Priority < b.Priority || (a.Priority == b.Priority && a.Index < b.Index);
            public void Push(int index, double priority)
            {
                var entry = new Entry(index, priority); int child = entries.Count;
                entries.Add(entry);
                while (child > 0)
                {
                    int parent = (child - 1) / 2;
                    if (!Before(entry, entries[parent])) break;
                    entries[child] = entries[parent]; child = parent;
                }
                entries[child] = entry;
            }
            public int Pop()
            {
                int result = entries[0].Index, last = entries.Count - 1;
                var entry = entries[last]; entries.RemoveAt(last);
                if (last == 0) return result;
                int parent = 0;
                while (parent * 2 + 1 < entries.Count)
                {
                    int child = parent * 2 + 1;
                    if (child + 1 < entries.Count && Before(entries[child + 1], entries[child])) child++;
                    if (!Before(entries[child], entry)) break;
                    entries[parent] = entries[child]; parent = child;
                }
                entries[parent] = entry;
                return result;
            }
        }
    }
}
