package btools.router;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Translate the pinned BRouter engine's package-local turn hints to the shared directions contract. */
public final class NavKurdDirections {
    private RoutingEngine active;
    private boolean cancelled;

    public synchronized void cancel() {
        cancelled = true;
        if (active != null) active.terminate();
    }

    public Map<String, Object> calculate(File segments, File profiles, String mode,
                                         double[] longitudes, double[] latitudes, int memoryMb) {
        String profile;
        switch (mode) {
            case "car": profile = "car-fast.brf"; break;
            case "walking": profile = "hiking-mountain.brf"; break;
            case "bicycle": profile = "trekking.brf"; break;
            default: throw new IllegalArgumentException("Unknown travel mode");
        }
        RoutingContext context = new RoutingContext();
        context.localFunction = new File(profiles, profile).getAbsolutePath();
        if ("walking".equals(mode)) {
            context.keyValues = new HashMap<>();
            context.keyValues.put("SAC_scale_limit", "0");
            context.keyValues.put("SAC_scale_preferred", "0");
            context.keyValues.put("hiking_routes_preference", "0");
        }
        context.memoryclass = Math.max(24, Math.min(96, memoryMb));
        context.turnInstructionMode = 3;
        List<OsmNodeNamed> stops = new RoutingParamCollector().readPositions(longitudes, latitudes);
        RoutingEngine engine = new RoutingEngine(null, null, segments, stops, context);
        engine.quite = true;
        synchronized (this) {
            if (cancelled) return status("Cancelled");
            active = engine;
        }
        try {
            engine.doRun(40_000);
            synchronized (this) {
                if (cancelled) return status("Cancelled");
            }
            String error = engine.getErrorMessage();
            if (error != null) {
                String detail = error.toLowerCase(Locale.ROOT);
                return status(detail.contains("not mapped") || detail.contains("no track") ||
                        detail.contains("not found within") ? "NoRoute" : "Unavailable");
            }
            OsmTrack track = engine.getFoundTrack();
            if (track == null || track.nodes.size() < 2 || track.distance <= 0) return status("NoRoute");
            return directions(track);
        } finally {
            synchronized (this) { active = null; }
        }
    }

    private static Map<String, Object> status(String code) {
        return new HashMap<>(Collections.singletonMap("code", code));
    }

    private static Map<String, Object> directions(OsmTrack track) {
        int count = track.nodes.size();
        List<List<Double>> path = new ArrayList<>(count);
        double[] distance = new double[count];
        for (int i = 0; i < count; i++) {
            OsmPathElement point = track.nodes.get(i);
            path.add(Arrays.asList(point.getILon() / 1_000_000d - 180, point.getILat() / 1_000_000d - 90));
            if (i > 0) distance[i] = distance[i - 1] + point.calcDistance(track.nodes.get(i - 1));
        }
        if (distance[count - 1] <= 0) return status("NoRoute");
        double scale = track.distance / distance[count - 1];
        List<Map<String, Object>> steps = new ArrayList<>();
        Map<String, Object> previous = step("depart", "straight", 0, path.get(0));
        steps.add(previous);
        int lastIndex = 0;
        if (track.voiceHints != null) {
            for (VoiceHint hint : track.voiceHints.list) {
                int index = hint.indexInTrack;
                if (index <= lastIndex || index >= count - 1) continue;
                String modifier = modifier(hint.cmd);
                if (modifier == null) continue;
                previous.put("distance", (distance[index] - distance[lastIndex]) * scale);
                previous = step(hint.isRoundabout() ? "roundabout" : "turn", modifier,
                        Math.abs(hint.getExitNumber()), path.get(index));
                steps.add(previous);
                lastIndex = index;
            }
        }
        previous.put("distance", (distance[count - 1] - distance[lastIndex]) * scale);
        steps.add(step("arrive", "straight", 0, path.get(count - 1)));
        Map<String, Object> geometry = new HashMap<>();
        geometry.put("type", "LineString");
        geometry.put("coordinates", path);
        Map<String, Object> route = new HashMap<>();
        route.put("geometry", geometry);
        route.put("distance", track.distance);
        route.put("duration", track.getTotalSeconds());
        route.put("legs", Collections.singletonList(Collections.singletonMap("steps", steps)));
        Map<String, Object> result = status("Ok");
        result.put("routes", Collections.singletonList(route));
        return result;
    }

    private static Map<String, Object> step(String type, String modifier, int exit, List<Double> location) {
        Map<String, Object> maneuver = new HashMap<>();
        maneuver.put("type", type);
        maneuver.put("modifier", modifier);
        maneuver.put("location", location);
        if (exit > 0) maneuver.put("exit", exit);
        Map<String, Object> result = new HashMap<>();
        result.put("maneuver", maneuver);
        result.put("distance", 0d);
        return result;
    }

    private static String modifier(int command) {
        switch (command) {
            case VoiceHint.TL: case VoiceHint.KL: case VoiceHint.EL: return "left";
            case VoiceHint.TSLL: return "slight left";
            case VoiceHint.TSHL: return "sharp left";
            case VoiceHint.TR: case VoiceHint.KR: case VoiceHint.ER: return "right";
            case VoiceHint.TSLR: return "slight right";
            case VoiceHint.TSHR: return "sharp right";
            case VoiceHint.TU: case VoiceHint.TLU: case VoiceHint.TRU: return "uturn";
            case VoiceHint.C: case VoiceHint.RNDB: case VoiceHint.RNLB: return "straight";
            default: return null;
        }
    }
}
