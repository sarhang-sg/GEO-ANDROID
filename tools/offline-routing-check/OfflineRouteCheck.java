import btools.router.NavKurdDirections;
import java.io.File;
import java.util.List;
import java.util.Map;

/** Exercise the production router between two road locations in central Erbil. */
public final class OfflineRouteCheck {
    public static void main(String[] args) {
        File graph = new File(args[0]);
        File profiles = new File(args[1]);
        for (String mode : new String[]{"car", "walking", "bicycle"}) {
            NavKurdDirections router = new NavKurdDirections();
            Map<?, ?> response = router.calculate(graph, profiles, mode,
                    new double[]{44.0079, 44.0235}, new double[]{36.1901, 36.1848}, 48);
            if (!"Ok".equals(response.get("code"))) throw new AssertionError(mode + ": " + response.get("code"));
            Map<?, ?> route = (Map<?, ?>) ((List<?>) response.get("routes")).get(0);
            List<?> path = (List<?>) ((Map<?, ?>) route.get("geometry")).get("coordinates");
            int meters = ((Number) route.get("distance")).intValue();
            int seconds = ((Number) route.get("duration")).intValue();
            Map<?, ?> leg = (Map<?, ?>) ((List<?>) route.get("legs")).get(0);
            List<?> steps = (List<?>) leg.get("steps");
            if (path.size() < 8 || meters < 1400 || meters > 10_000 || seconds <= 0 || steps.size() < 3)
                throw new AssertionError("Incomplete " + mode + " route");
            double total = 0;
            for (Object obj : steps) total += ((Number) ((Map<?, ?>) obj).get("distance")).doubleValue();
            if (Math.abs(total - meters) > 1) throw new AssertionError("Inconsistent maneuver distances");
            System.out.println(mode + ": " + meters + " m, " + seconds + " s, " + path.size() + " points, " + steps.size() + " steps");
        }
    }
}
