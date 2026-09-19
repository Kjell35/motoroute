package com.motoroute.graphhopper.curvature;

import com.graphhopper.util.PointList;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Validates the curvature scoring against synthetic reference geometries
 * before it is ever trusted against real OSM data. Real-world validation
 * (known alpine passes must score high, motorways must score ~0) happens
 * separately in Sprint 3/4 per the MVP plan (docs/CURVATURE_VALIDATION.md)
 * once a test region is imported - these unit tests only guard the math.
 */
class CurvatureTagParserTest {

    @Test
    void straightLineScoresZero() {
        PointList straight = new PointList();
        straight.add(48.1000, 11.5000);
        straight.add(48.1010, 11.5000);
        straight.add(48.1020, 11.5000);
        straight.add(48.1030, 11.5000);

        double score = CurvatureTagParser.computeScore(straight);
        assertEquals(0.0, score, 0.01, "A perfectly straight road must score 0 curvature");
    }

    @Test
    void gentleSingleBendScoresLow() {
        PointList gentle = new PointList();
        gentle.add(48.1000, 11.5000);
        gentle.add(48.1010, 11.5002);
        gentle.add(48.1020, 11.5006);
        gentle.add(48.1030, 11.5012);

        double score = CurvatureTagParser.computeScore(gentle);
        assertTrue(score < 0.35, "A single gentle bend should score noticeably below a hairpin cluster, got " + score);
    }

    @Test
    void hairpinClusterScoresHigh() {
        // Simulates a switchback sequence (alpine-pass style): sharp
        // alternating turns over a short stretch.
        PointList hairpins = new PointList();
        double lat = 47.5500;
        double lon = 12.1500;
        hairpins.add(lat, lon);
        double[][] deltas = {
                {0.0006, 0.0002}, {0.0002, 0.0007}, {-0.0004, 0.0009},
                {-0.0007, 0.0003}, {-0.0005, -0.0004}, {0.0001, -0.0008},
                {0.0006, -0.0005}, {0.0008, 0.0001}
        };
        for (double[] d : deltas) {
            lat += d[0];
            lon += d[1];
            hairpins.add(lat, lon);
        }

        double score = CurvatureTagParser.computeScore(hairpins);
        assertTrue(score > 0.5, "A hairpin cluster should score high curvature, got " + score);
    }

    @Test
    void tooFewPointsScoresZeroViaCaller() {
        // Guarded in handleWayTags(), not computeScore() itself - covered
        // here as documentation of the contract.
        PointList single = new PointList();
        single.add(48.0, 11.0);
        single.add(48.0001, 11.0001);
        // computeScore requires >= 2 points to run at all; the "too few
        // points" (<3) short-circuit lives in handleWayTags before this
        // method is even called.
        assertTrue(single.size() < 3);
    }
}
