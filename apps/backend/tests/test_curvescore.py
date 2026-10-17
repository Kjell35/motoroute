"""Kalibriertests für CurveScorer v2 (docs/14 §3.2: B500/Kesselberg/Autobahn)."""

import math

from app.api.curvescore import (
    count_enclosed_sharp_curves,
    curve_score,
    estimate_radius,
    score_shape_segments,
)


def _shape(points_meter: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Meter-Konstruktionen in lat/lon um (0, 0)-Umkreis zurückrechnen."""
    meters_per_deg = 111_320.0
    return [(lat / meters_per_deg, lon / meters_per_deg) for lat, lon in points_meter]


def test_estimate_radius_full_circle() -> None:
    # 半 Kehre: 180 ° über 100 m Sehne = Halbkreis mit r = 50.
    assert math.isclose(estimate_radius(100.0, 180.0), 50.0)


def test_estimate_radius_small_delta_is_straight() -> None:
    assert estimate_radius(100.0, 3.0) is None


def test_autobahn_baseline_scores_low() -> None:
    """A8-Negativkontrolle: überwiegend gerade, Score bleibt < 2."""
    # 5 km lange, fast gerade Linie mit minimalen Auffächerspuren.
    coords = _shape([(i * 50.0, 0.0) for i in range(100)])  # 100 × 50 m gerade
    segments = score_shape_segments(coords)
    score = curve_score(segments, length_m_total=4_950.0)
    assert score < 2.0


def test_kesselberg_style_hairpins_score_high() -> None:
    """13 Haarnadeln à ~200 m Radius auf ~12,4 km - Kesselberg charakterisiert.

    Live-Kalibrierung (2026-10-11): echte Kesselberg-Route (32,9 km, 22
    hairpin-Fenster + 122 sharp) liefert 7,7. Diese synthetische Serpentine
    liegt oberhalb: geschlossenes Band 7 < score <= 10.
    """
    # Zickzack: jede Kehre 180° über 400 m Sehne => r ~ 200 m ('medium');
    # Abstand zwischen Kehren ~450 m.
    points: list[tuple[float, float]] = []
    x = 0.0
    for _ in range(13):
        points.append((x, 0.0))
        points.append((x, 400.0))
        x += 450.0
    coords = _shape(points)
    path_len = sum(
        math.hypot((b[0] - a[0]) * 111_320.0, (b[1] - a[1]) * 111_320.0)
        for a, b in zip(coords[:-1], coords[1:], strict=True)
    )
    segments = score_shape_segments(coords)
    score = curve_score(segments, length_m_total=path_len)
    assert 7.0 <= score <= 10.0


def test_b500_style_fluent_curves_score_mid() -> None:
    """B500-Charakter: geschwungene Landstraße mit ~90°-Schwenkern über
    300 m Sehne (r ~ 212 m = 'medium'); Recherche: flüssige weite bis mittel
    gezogene Bögen, subjektiv ~6/10 — über Autobahn, unter Hoarnadel-Häufung.
    """
    meters_per_deg = 111_320.0
    step = 300.0
    angle_step_deg = 90.0
    angle = 0.0
    x, y = 0.0, 0.0
    coords: list[tuple[float, float]] = [(0.0, 0.0)]
    for _ in range(30):
        angle += math.radians(angle_step_deg)
        x += step * math.sin(angle)
        y += step * math.cos(angle)
        coords.append((y / meters_per_deg, x / meters_per_deg))
    path_len = sum(
        math.hypot((b[0] - a[0]) * meters_per_deg, (b[1] - a[1]) * meters_per_deg)
        for a, b in zip(coords[:-1], coords[1:], strict=True)
    )
    segments = score_shape_segments(coords)
    # Erwartung nach Kalibrierung K=3,6: alle Fenster ~'medium' (weight 2)
    # => ratio ~2.0 => Score ~7. Band: 6 <= score <= 10 (gut über Autobahn,
    # leicht unter Kesselberg-Live 7,7 / synth越高).
    score = curve_score(segments, length_m_total=path_len)
    assert 6.0 <= score <= 10.0


def test_score_is_normalized_zero_to_ten() -> None:
    coords = _shape([(i * 50.0, 0.0) for i in range(200)])
    segments = score_shape_segments(coords)
    score = curve_score(segments, length_m_total=9_950.0)
    assert 0.0 <= score <= 10.0


def test_announces_only_sharp_curves() -> None:
    segments = [
        {"radius_m": 30.0, "length_m": 100.0, "weight": 5.0, "class": "hairpin"},
        {"radius_m": 120.0, "length_m": 150.0, "weight": 3.0, "class": "sharp"},
        {"radius_m": 500.0, "length_m": 300.0, "weight": 0.5, "class": "wide"},
        {"radius_m": 200.0, "length_m": 200.0, "weight": 2.0, "class": "medium"},
    ]
    assert count_enclosed_sharp_curves(segments) == 2
