using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port.Editor
{
    public static class OrbRoomNavigationChecks
    {
        public static int Run()
        {
            int count = 0;
            Action<bool, string> check = (ok, label) => { if (!ok) throw new InvalidOperationException("Orb room: " + label); count++; };
            var room = Box(-3, 0, -3, 3, 4, 3);
            var home = V(-2, 1, 0);
            var target = Target("lamp", V(2, 1, 0));
            var barrier = Box(-.25, 0, -3, .25, 2, 3);
            var navigation = new OrbRoomNavigation(.3);
            navigation.SetScene("room-a", 1, room, new[] { barrier }, new[] { target }, home);
            var token = navigation.GetTargetRef("lamp");
            check(token.SpaceID == "room-a" && token.SceneRevision == 1 && token.TargetID == "lamp" && token.Generation == 1,
                "object reference carries exact scene and generation");
            check(!navigation.IsSegmentFree(home, target.Approach), "straight line is blocked by inflated furniture");
            check(!navigation.IsPositionFree(V(.54, 1, 0)), "body radius expands obstacle clearance");
            check(navigation.IsPositionFree(V(.56, 1, 0)), "point outside inflated box is free");
            check(!navigation.IsSegmentFree(V(.54, 1, 0), V(2, 1, 0)), "unsafe start cannot be smoothed into a route");
            check(!navigation.IsSegmentFree(V(2, 1, 0), V(.54, 1, 0)), "unsafe end cannot be smoothed into a route");
            check(!navigation.IsPositionFree(V(-2.8, 1, 0)), "room edge retains complete body clearance");
            check(!navigation.IsSegmentFree(home, V(double.NaN, 1, 0)), "nonfinite segment is refused");
            check(navigation.SelectTarget(token), "three-dimensional path around the barrier exists");
            var trip = Finish(navigation, 20);
            check(trip.Safe, "every movement segment retains swept body clearance");
            check(trip.Arrived && Near(navigation.Center, target.Approach), "movement reaches exact object approach");
            check(trip.MaximumY > 2.3, "route rises above wall that spans the full room depth");
            check(navigation.SelectedTarget == target && navigation.State == "Inspecting Lamp", "arrival retains local object selection");
            check(navigation.ReturnHome(), "return reuses collision-aware planner");
            trip = Finish(navigation, 20);
            check(trip.Safe && trip.Arrived && Near(navigation.Center, home), "return completes without crossing furniture");
            check(navigation.SelectedTarget == null && navigation.State == "At home", "return clears the target highlight owner");

            var corner = new OrbRoomNavigation(.3);
            corner.SetScene("corner", 1, room, new[] { Box(-.3, 0, -.3, .3, 3, .3) }, Array.Empty<OrbRoomTarget>(), V(-1, 1, -1));
            check(!corner.IsSegmentFree(V(-1, 1, .1), V(.1, 1, -1)), "diagonal corner clipping is refused");
            check(corner.IsSegmentFree(V(-1, 1, -1), V(-1, 2, 1)), "parallel movement beside an obstacle is accepted");

            var sealedRoom = new OrbRoomNavigation(.3);
            sealedRoom.SetScene("blocked", 1, room, new[] { Box(-.25, 0, -3, .25, 4, 3) }, new[] { target }, home);
            check(!sealedRoom.SelectTarget(sealedRoom.GetTargetRef("lamp")), "unreachable object returns no route");
            check(!sealedRoom.IsMoving && Near(sealedRoom.Center, home) && sealedRoom.SelectedTarget == target,
                "unreachable known object may highlight but cannot teleport the body");
            check(!sealedRoom.Explore() && !sealedRoom.IsExploring && !sealedRoom.IsMoving
                && sealedRoom.SelectedTarget == null && Near(sealedRoom.Center, home), "an entirely unreachable tour stops after one bounded pass");

            CheckFreshness(check, room, home, target);
            CheckTime(check);
            CheckRoomLayout(check);
            CheckViewport(check);
            Debug.Log("ARCHI_ORB_ROOM_NAVIGATION_CHECKS " + count);
            return count;
        }

        private static void CheckFreshness(Action<bool, string> check, OrbBounds3 room, OrbVector3 home, OrbRoomTarget target)
        {
            var navigation = new OrbRoomNavigation(.3);
            var sourceTargets = new[] { target };
            var sourceObstacles = new[] { Box(-.25, 0, -3, .25, 2, 3) };
            navigation.SetScene("a", 1, room, sourceObstacles, sourceTargets, home);
            var original = navigation.GetTargetRef(target.Id);
            navigation.SelectTarget(original);
            navigation.Tick(1.0 / 30);
            var before = navigation.Center;
            string beforeState = navigation.State;
            check(!navigation.SelectTarget(new OrbTargetRef("other", 1, target.Id, 1))
                && !navigation.SelectTarget(new OrbTargetRef("a", 2, target.Id, 1))
                && !navigation.SelectTarget(new OrbTargetRef("a", 1, target.Id, 2))
                && !navigation.SelectTarget(new OrbTargetRef("a", 1, "missing", 1)), "space, revision, object and generation mismatches are refused");
            check(Near(navigation.Center, before) && navigation.SelectedTarget == target && navigation.State == beforeState && navigation.IsMoving,
                "bad object references leave current movement untouched");
            sourceTargets[0] = Target("replacement", V(1, 1, 1));
            sourceObstacles[0] = Box(20, 20, 20, 21, 21, 21);
            check(navigation.Targets[0] == target && !navigation.IsSegmentFree(home, target.Approach),
                "mutating supplied arrays cannot change the active scene");

            check(Rejects(() => navigation.SetScene("a", 1, room, Array.Empty<OrbBounds3>(), new[] { target }, home)),
                "same scene revision is rejected");
            check(Rejects(() => navigation.SetScene("a", 0, room, Array.Empty<OrbBounds3>(), new[] { target }, home)),
                "invalid revision is rejected");
            check(Rejects(() => navigation.SetScene("a", 2, room, Array.Empty<OrbBounds3>(), new[] { target, target }, home)),
                "duplicate object IDs reject replacement");
            check(Rejects(() => navigation.SetScene("a", 2, room, new[] { Box(double.NaN, 0, 0, 1, 1, 1) }, new[] { target }, home)),
                "nonfinite geometry rejects replacement");
            check(Rejects(() => navigation.SetScene("a", 2, room, new[] { Box(-2.1, .9, -.1, -1.9, 1.1, .1) }, new[] { target }, home)),
                "obstructed home rejects replacement");
            check(Rejects(() => navigation.SetScene("a", 2, room, new[] { Box(1.9, .9, -.1, 2.1, 1.1, .1) }, new[] { target }, home)),
                "obstructed object approach rejects replacement");
            check(Rejects(() => navigation.SetScene("a", 2, room, Array.Empty<OrbBounds3>(),
                new[] { new OrbRoomTarget("lamp", "Lamp", target.Bounds, target.Approach, 0) }, home)), "zero generation rejects replacement");
            check(Near(navigation.Center, before) && navigation.SelectedTarget == target && navigation.State == beforeState && navigation.SceneRevision == 1,
                "all invalid replacements preserve the entire current scene and route");

            var replacement = new OrbRoomTarget("lamp", "Moved lamp", target.Bounds, V(2, 2, 1), 2);
            navigation.SetScene("a", 2, room, Array.Empty<OrbBounds3>(), new[] { replacement }, home);
            check(!navigation.IsMoving && navigation.SelectedTarget == null && Near(navigation.Center, home),
                "new scene cancels old route and object highlight");
            check(!navigation.SelectTarget(original), "old reference cannot bind a reused object ID");
            check(!navigation.SelectTarget(new OrbTargetRef("a", 2, "lamp", 1)), "old generation cannot bind current scene revision");
            check(navigation.SelectTarget(navigation.GetTargetRef("lamp")), "fresh replacement reference works");
            navigation.SetScene("b", 1, room, Array.Empty<OrbBounds3>(), new[] { replacement }, home);
            check(Rejects(() => navigation.SetScene("a", 2, room, Array.Empty<OrbBounds3>(), new[] { target }, home)),
                "A to B to A cannot revive a retired scene revision");
            navigation.SetScene("a", 3, room, Array.Empty<OrbBounds3>(), new[] { target }, home);
            check(!navigation.SelectTarget(original) && navigation.SelectTarget(navigation.GetTargetRef("lamp")),
                "reentered space requires a fresh reference");

            var distantBounds = new OrbRoomTarget("window", "Window", Box(-1, 1, 3.01, 1, 3, 3.04), V(0, 2, 2));
            navigation.SetScene("a", 4, room, Array.Empty<OrbBounds3>(), new[] { distantBounds }, home);
            check(navigation.SelectTarget(navigation.GetTargetRef("window")), "display bounds can lie outside center-navigation volume");
            navigation.Cancel();
            check(!navigation.IsMoving && !navigation.IsExploring && navigation.SelectedTarget == null, "cancel retires local intent without replacing scene");
            var bounded = new OrbRoomNavigation(.3);
            for (int i = 0; i < 64; i++) bounded.SetScene("space-" + i, 1, room, Array.Empty<OrbBounds3>(), Array.Empty<OrbRoomTarget>(), home);
            check(Rejects(() => bounded.SetScene("space-64", 1, room, Array.Empty<OrbBounds3>(), Array.Empty<OrbRoomTarget>(), home))
                && bounded.SpaceID == "space-63", "replay fence is bounded and fails closed without evicting old spaces");
            bounded.SetScene("space-0", 2, room, Array.Empty<OrbBounds3>(), Array.Empty<OrbRoomTarget>(), home);
            check(bounded.SpaceID == "space-0" && bounded.SceneRevision == 2, "known spaces can advance at replay-fence capacity");
        }

        private static void CheckTime(Action<bool, string> check)
        {
            var first = EmptyTrip();
            var second = EmptyTrip();
            for (int i = 0; i < 60; i++) first.Tick(1.0 / 60);
            for (int i = 0; i < 120; i++) second.Tick(1.0 / 120);
            check(Near(first.Center, second.Center, 1e-9), "fixed steps agree across ordinary frame rates");
            var before = first.Center;
            first.Tick(double.NaN); first.Tick(double.PositiveInfinity); first.Tick(-1); first.Tick(0);
            check(Near(first.Center, before), "nonfinite and nonpositive time cannot move the body");
            first.Tick(100, true);
            check(Near(first.Center, before) && first.IsMoving, "pause holds center and preserves pending route");
            first.Tick(1.0 / 120);
            check(OrbVector3.Distance(first.Center, before) <= 1.25 / 120 + 1e-9, "resume has no paused-time catchup");
            before = first.Center;
            first.Tick(100);
            check(OrbVector3.Distance(first.Center, before) <= 1.25 * OrbRoomNavigation.FixedStep * OrbRoomNavigation.MaximumCatchUpSteps + 1e-9,
                "a stalled frame consumes at most eight bounded steps");
            first.Cancel();
            before = first.Center;
            first.Tick(1);
            check(Near(first.Center, before), "cancelled movement stays still");
        }

        private static void CheckRoomLayout(Action<bool, string> check)
        {
            var bounds = Box(-3.45, 0, -1.7, 3.45, 3.6, 4.85);
            var desk = Box(.85, .63, .575, 2.45, .73, 1.425);
            var deskLegA = Box(.96, -.05, .65, 1.04, .65, 1.35);
            var deskLegB = Box(2.26, -.05, .65, 2.34, .65, 1.35);
            var shelf = Box(-2.75, .05, 2.075, -1.45, 2.05, 2.725);
            var lamp = Box(1.76, .73, .85, 2.24, 1.43, 1.25);
            var targets = new[] {
                new OrbRoomTarget("desk", "Desk", desk, V(1.55, 1.45, -.1)),
                new OrbRoomTarget("shelf", "Archive", shelf, V(-1.65, 1.65, 1.15)),
                new OrbRoomTarget("lamp", "Lamp", lamp, V(1.45, 2.25, .95)),
                new OrbRoomTarget("window", "Window", Box(-1.15, 1.125, 4.90, 1.15, 2.675, 4.94), V(0, 2.35, 3.9)) };
            foreach (var home in new[] { V(0, 1.35, 0), V(.45, 1.35, -.35) })
            {
                var navigation = new OrbRoomNavigation(.64);
                navigation.SetScene("desktop-room", 1, bounds, new[] { desk, deskLegA, deskLegB, shelf, lamp }, targets, home);
                bool reachable = true, safe = true;
                foreach (var target in targets)
                {
                    reachable &= navigation.SelectTarget(navigation.GetTargetRef(target.Id));
                    var visit = Finish(navigation, 20);
                    reachable &= visit.Arrived && Near(navigation.Center, target.Approach);
                    safe &= visit.Safe;
                }
                check(reachable && safe, "authored room objects reachable with swept clearance from home " + home.X);
                navigation.ReturnHome();
                check(Finish(navigation, 20).Safe && Near(navigation.Center, home), "authored room returns to home " + home.X);
                check(navigation.Explore(), "authored room exploration starts from home " + home.X);
                var visited = new HashSet<string>(StringComparer.Ordinal);
                string inspecting = null;
                int visits = 0;
                safe = true;
                for (int frame = 0; frame < 6000 && (navigation.IsExploring || navigation.IsMoving); frame++)
                {
                    var before = navigation.Center;
                    navigation.Tick(1.0 / 60);
                    safe &= navigation.IsSegmentFree(before, navigation.Center);
                    if (navigation.SelectedTarget != null && !navigation.IsMoving)
                    {
                        if (inspecting != navigation.SelectedTarget.Id) { visits++; visited.Add(navigation.SelectedTarget.Id); }
                        inspecting = navigation.SelectedTarget.Id;
                    }
                    else inspecting = null;
                }
                check(safe && visited.Count == targets.Length && visits == targets.Length && !navigation.IsExploring && !navigation.IsMoving
                    && navigation.SelectedTarget == null && Near(navigation.Center, home) && navigation.State == "Exploration complete",
                    "exploration visits once, finishes and returns home " + home.X);
                var finished = navigation.Center;
                for (int i = 0; i < 120; i++) navigation.Tick(1.0 / 60);
                check(Near(navigation.Center, finished) && !navigation.IsExploring, "finished exploration stays at rest " + home.X);
            }
        }

        private static void CheckViewport(Action<bool, string> check)
        {
            check(OrbRoomViewport.TryNormalize(200, 200, 400, 400, 960, 720, out var u, out var v)
                && Math.Abs(u - .5) < 1e-9 && Math.Abs(v - .5) < 1e-9, "square panel maps image center");
            check(!OrbRoomViewport.TryNormalize(200, 49, 400, 400, 960, 720, out u, out v)
                && !OrbRoomViewport.TryNormalize(200, 351, 400, 400, 960, 720, out u, out v), "square panel rejects top and bottom letterbox gutters");
            check(OrbRoomViewport.TryNormalize(0, 50, 400, 400, 960, 720, out u, out v) && u == 0 && v == 1
                && OrbRoomViewport.TryNormalize(400, 350, 400, 400, 960, 720, out u, out v) && u == 1 && v == 0,
                "image boundaries map with Unity vertical flip");
            check(!OrbRoomViewport.TryNormalize(132, 150, 800, 400, 960, 720, out u, out v)
                && !OrbRoomViewport.TryNormalize(668, 150, 800, 400, 960, 720, out u, out v), "wide panel rejects side gutters");
            check(OrbRoomViewport.TryNormalize(400, 100, 800, 400, 960, 720, out u, out v)
                && Math.Abs(u - .5) < 1e-9 && Math.Abs(v - .75) < 1e-9, "wide panel preserves correct viewport coordinates");
            check(!OrbRoomViewport.TryNormalize(0, 0, 0, 400, 960, 720, out u, out v)
                && !OrbRoomViewport.TryNormalize(0, 0, 400, 400, 960, 0, out u, out v)
                && !OrbRoomViewport.TryNormalize(double.NaN, 0, 400, 400, 960, 720, out u, out v)
                && !OrbRoomViewport.TryNormalize(0, 0, double.PositiveInfinity, 400, 960, 720, out u, out v),
                "invalid viewport dimensions and coordinates are refused");
        }

        private static OrbRoomNavigation EmptyTrip()
        {
            var navigation = new OrbRoomNavigation(.3);
            var target = Target("far", V(8, 3, 8));
            navigation.SetScene("empty", 1, Box(0, 0, 0, 10, 5, 10), Array.Empty<OrbBounds3>(), new[] { target }, V(1, 1, 1));
            navigation.SelectTarget(navigation.GetTargetRef("far"));
            return navigation;
        }
        private readonly struct Trip
        {
            public readonly bool Safe, Arrived;
            public readonly double MaximumY;
            public Trip(bool safe, bool arrived, double maximumY) { Safe = safe; Arrived = arrived; MaximumY = maximumY; }
        }
        private static Trip Finish(OrbRoomNavigation navigation, int seconds)
        {
            bool safe = true;
            double maximumY = navigation.Center.Y;
            for (int frame = 0; frame < seconds * 60 && navigation.IsMoving; frame++)
            {
                var before = navigation.Center;
                navigation.Tick(1.0 / 60);
                safe &= navigation.IsPositionFree(navigation.Center) && navigation.IsSegmentFree(before, navigation.Center);
                maximumY = Math.Max(maximumY, navigation.Center.Y);
            }
            return new Trip(safe, !navigation.IsMoving, maximumY);
        }
        private static bool Rejects(Action action) { try { action(); return false; } catch (ArgumentException) { return true; } }
        private static bool Near(OrbVector3 a, OrbVector3 b, double epsilon = .00002) => OrbVector3.Distance(a, b) <= epsilon;
        private static OrbVector3 V(double x, double y, double z) => new OrbVector3(x, y, z);
        private static OrbBounds3 Box(double x0, double y0, double z0, double x1, double y1, double z1) => new OrbBounds3(V(x0, y0, z0), V(x1, y1, z1));
        private static OrbRoomTarget Target(string id, OrbVector3 approach) => new OrbRoomTarget(id, char.ToUpperInvariant(id[0]) + id.Substring(1),
            new OrbBounds3(approach - V(.1, .1, .1), approach + V(.1, .1, .1)), approach);
    }
}
