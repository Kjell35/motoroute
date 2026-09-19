package com.motoroute.graphhopper.curvature;

import com.graphhopper.routing.ev.DecimalEncodedValue;
import com.graphhopper.routing.ev.DecimalEncodedValueImpl;

/**
 * Custom encoded value that stores a normalized curvature score (0.0 - 1.0)
 * per road edge, derived from the OSM way geometry during import.
 *
 * 0.0  = perfectly straight segment
 * 1.0  = maximum observed curvature (heavy switchbacks / hairpins)
 *
 * This is NOT a standard OSM tag - it is computed once at import time by
 * {@link CurvatureTagParser} from the raw point sequence of each way and
 * baked into the graph as a first-class edge property, exactly like
 * road_class or surface. This is what makes "kurvig" / "extra kurvig"
 * usable as a routing weight instead of a cosmetic map overlay.
 *
 * Rationale for a custom EncodedValue instead of GraphHopper's
 * custom_model "areas" mechanism: areas are coarse (polygon-based,
 * hand-drawn or precomputed buffers) and don't scale to a whole country's
 * road network at per-edge granularity. A real encoded value lets every
 * fahrstil profile reference curvature directly in its custom_model
 * priority expression, per edge, like any built-in attribute.
 */
public final class Curvature {

    public static final String KEY = "curvature";

    // 5 bits -> 32 discrete buckets is enough resolution for routing
    // weighting purposes while keeping the graph compact.
    public static DecimalEncodedValue create() {
        return new DecimalEncodedValueImpl(KEY, 5, 0, 1.0 / 31.0, false, false, true);
    }

    private Curvature() {
    }
}
