package com.motoroute.graphhopper.curvature;

import com.graphhopper.reader.ReaderWay;
import com.graphhopper.routing.ev.DecimalEncodedValue;
import com.graphhopper.routing.ev.EdgeIntAccess;
import com.graphhopper.routing.util.parsers.TagParser;
import com.graphhopper.storage.IntsRef;
import com.graphhopper.util.PointList;

/**
 * Computes a curvature score for a way during graph import and writes it
 * into the {@link Curvature} encoded value.
 *
 * Method: sinuosity, the industry-standard proxy used by curvy-road
 * routing tools (this is the same core idea BRouter/Kurviger use for
 * their "kurvig" profiles) -
 *
 *   sinuosity = actual path length / straight-line (chord) distance
 *
 * A perfectly straight road has sinuosity 1.0. A hairpin-laden mountain
 * pass can exceed 2.0-3.0. We additionally weight in the *frequency* of
 * heading changes above a threshold angle, so a road with one long gentle
 * bend scores lower than a road with many tight successive turns of the
 * same total length - which matches what riders actually mean by "kurvig"
 * vs. "extra kurvig".
 *
 * This runs once per way at import time (offline, batch), not at
 * request time - so it has zero runtime routing-latency cost.
 */
public final class CurvatureTagParser implements TagParser {

    // Below this heading-change threshold (degrees between consecutive
    // segments) a direction change is treated as noise / GPS jitter in
    // the source geometry, not a "curve".
    private static final double MIN_TURN_ANGLE_DEG = 8.0;

    // Empirically chosen normalization ceiling for the combined score;
    // values above this are clamped to 1.0. Tune against real reference
    // routes (e.g. known alpine passes) during validation, see
    // docs/CURVATURE_VALIDATION.md.
    private static final double SCORE_CEILING = 3.2;

    private final DecimalEncodedValue curvatureEnc;

    public CurvatureTagParser(DecimalEncodedValue curvatureEnc) {
        this.curvatureEnc = curvatureEnc;
    }

    @Override
    public void handleWayTags(int edgeId, EdgeIntAccess edgeIntAccess, ReaderWay way, IntsRef relationFlags) {
        PointList points = way.getTag("point_list", null);
        double score;
        if (points == null || points.size() < 3) {
            // Straight-line or unknown geometry: no curvature signal.
            score = 0.0;
        } else {
            score = computeScore(points);
        }
        curvatureEnc.setDecimal(false, edgeId, edgeIntAccess, score);
    }

    /**
     * Package-private for unit testing without needing a full ReaderWay.
     */
    static double computeScore(PointList points) {
        double pathLength = 0.0;
        double turnWeightedSum = 0.0;

        double prevLat = points.getLat(0);
        double prevLon = points.getLon(0);
        Double prevBearing = null;

        for (int i = 1; i < points.size(); i++) {
            double lat = points.getLat(i);
            double lon = points.getLon(i);
            double segLen = haversineMeters(prevLat, prevLon, lat, lon);
            pathLength += segLen;

            double bearing = bearingDegrees(prevLat, prevLon, lat, lon);
            if (prevBearing != null) {
                double turn = angleDiffDegrees(prevBearing, bearing);
                if (turn >= MIN_TURN_ANGLE_DEG) {
                    // Weight sharper turns more than shallow ones, and
                    // scale by the segment length so a cluster of tight
                    // turns over a short stretch dominates the score -
                    // that is what "extra kurvig" riders are looking for.
                    turnWeightedSum += (turn / 180.0) * segLen;
                }
            }
            prevBearing = bearing;
            prevLat = lat;
            prevLon = lon;
        }

        double straightLineLength = haversineMeters(
                points.getLat(0), points.getLon(0),
                points.getLat(points.size() - 1), points.getLon(points.size() - 1));

        double sinuosity = straightLineLength > 1.0
                ? pathLength / straightLineLength
                : 1.0;

        double turnDensity = pathLength > 1.0
                ? turnWeightedSum / pathLength
                : 0.0;

        // Combine: sinuosity captures overall detour factor, turnDensity
        // captures how "busy" the road is with direction changes.
        // Both anchored at 0 for a straight road.
        double raw = (sinuosity - 1.0) + turnDensity;

        double normalized = Math.max(0.0, Math.min(1.0, raw / (SCORE_CEILING - 1.0)));
        return normalized;
    }

    private static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
        double r = 6371000.0;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return r * c;
    }

    private static double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
        double phi1 = Math.toRadians(lat1);
        double phi2 = Math.toRadians(lat2);
        double dLon = Math.toRadians(lon2 - lon1);
        double y = Math.sin(dLon) * Math.cos(phi2);
        double x = Math.cos(phi1) * Math.sin(phi2)
                - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLon);
        double theta = Math.atan2(y, x);
        return (Math.toDegrees(theta) + 360.0) % 360.0;
    }

    private static double angleDiffDegrees(double a, double b) {
        double diff = Math.abs(a - b) % 360.0;
        return diff > 180.0 ? 360.0 - diff : diff;
    }
}
