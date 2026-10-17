"""CurveScorer v2: fahrspaß-orientierte Kurvenbewertung von Valhalla-Routen.

Design: docs/14-m3-spike-avoidance-curvescore.md §3 (implementierungsplan):
- Kurvenverhalten wird über **Dreier-Fenster** aus der Geometrie bewertet
  (Richtungsänderung über 2 angrenzende Segmente), nicht über die
  Segment-End-Headings allein — sonst werden echte 180°-Kehren über
  Segmentgrenzen halbiert und fälschlich als langgezogen klassifiziert.
- Radius-Schätzung r = chord / (2·sin(Δ/2)). Klassen: Haarnadel <50 m,
  eng <150 m, mittel <400 m, weit ≥400 m; Live-Kalibrierte Gewichte
  5/3/2/0,3; Geraden-Fenster zählen 0 (Story: A8-Umgehung gegen Inflation).
- Route-Score: gewichtete Kurvenlänge pro km (K=3,6), normiert 0–10.
- Geometrie wird vor der Fensterung auf 25-m-Abstände resampelt —
  Valhalla-Stützpunkte sind ungleich verteilt (p50 14 m, max 250 m);
  ohne Resampling kippen dicht gepackte Kurvenknoten die Statistik.

Kalibriert an Live-Valhalla-Routen (2026-10-11, siehe docs/14 §5.3):
Kesselberg (~7,7), Sudelfeld (~6,4), Autobahn als Negativkontrolle (<2).
"""

from __future__ import annotations

import math
from typing import Any

# Kurvenklassen: Obergrenze Radius (m) -> Gewichtsfaktor (Live-Kalibrierung 2026-10-11).
# Gerade-Fenster tragen nicht zum Score bei (siehe curve_score).
_CLASS_BOUNDS = ((50.0, 5.0), (150.0, 3.0), (400.0, 2.0))
_WIDE_WEIGHT = 0.3     # r >= 400 m: leicht zählend (B500-artige weite Bögen)
_STRAIGHT_WEIGHT = 0.0  # Δ < 5° oder unmessbar

# Normierungskonstante: ratio=(Σ w·l)/l_total.
# Live-Kalibrierung (Valhalla 3.9.1, Bayern-Tiles, 2026-10-11):
#   Kesselberg  ratio 1.977 -> Score 7.7  (Erwartung ~8)   passt
#   Sudelfeld   ratio 1.638 -> Score 6.4  (Erwartung 5-6)  passt
#   A8 MUC->RO  ratio 0.168 -> Score 0.7  (Erwartung <2)    Negativkontrolle erfüllt
#   A8 Ulm->MUC ratio 0.437 -> Score 1.5  (Erwartung <2)    Negativkontrolle erfüllt
_NORM_K = 3.6

# Ein Segmente-Score über 10 wäre unplausibel; Clamp kalibrierungssicher.
_CLAMP_MAX = 10.0

# TTS-Ansage: Mindestklasse "enge Kurve" = r < 150 m.
_ANNOUNCE_MAX_RADIUS = 150.0

# ΔHeading unterhalb dessen wir den Abschnitt als Gerade zählen.
_DELTA_STRAIGHT_DEG = 5.0


def _wrap_degrees(delta: float) -> float:
    """Kürzester Winkel (0–180°) über 360°-Wrap."""
    delta = abs(delta) % 360.0
    if delta > 180.0:
        delta = 360.0 - delta
    return delta


def _class_weight(radius_m: float) -> float:
    for upper, weight in _CLASS_BOUNDS:
        if radius_m < upper:
            return weight
    return _WIDE_WEIGHT


def estimate_radius(chord_m: float, delta_deg: float) -> float | None:
    """Radius-Schätzung aus Sehne und Richtungsänderung.

    r = chord / (2·sin(Δ/2)); bei Δ→0 unmessbar (Gerade) -> None.
    """
    delta_deg = _wrap_degrees(delta_deg)
    if delta_deg < _DELTA_STRAIGHT_DEG or chord_m <= 0:
        return None  # als Gerade gewertet
    return chord_m / (2.0 * math.sin(math.radians(delta_deg / 2.0)))


def _resample(coords: list[tuple[float, float]], step_m: float = 25.0) -> list[tuple[float, float]]:
    """Resampelt die Roh-Geometrie auf ~gleichmäßige Punkt-Abstände.

    Kalibriert-tauglich: Valhalla-Shapes haben sehr ungleiche Punkt-Abstände
    (Mittenden 14 m, bis 250 m). Ohne Resampling fressen dichtgestopfte
    Kurvenknoten die Fenstersumme und Geraden austern zu viele kleine
    Δ-Headings in den 'straight'-Korb. 25 m resampelt: Δ-Heading-med. steigt
    von 5,8° auf 9,5°, Radius p-Median ins 'medium'-Fenster.
    """
    if len(coords) < 2:
        return list(coords)
    lat0, lon0 = coords[0]
    mlat = 111_320.0
    mlon = mlat * max(math.cos(math.radians(lat0)), 1e-6)
    pts = [((a - lat0) * mlat, (b - lon0) * mlon) for a, b in coords]
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        d = math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        acc += d
        if acc >= step_m:
            out.append(pts[i])
            acc = 0.0
    return out


def score_shape_segments(coords: list[tuple[float, float]]) -> list[dict[str, float | str]]:
    """Bewertet die Geometrie via Dreier-Fenster (2 angrenzende Segmente).

    Für jedes Dreier-Fenster (P0, P1, P2) gilt ΔHeading = Winkel zwischen
    Segment1 (P0→P1) und Segment2 (P1→P2); die Sehne ist P0–P2. So erfasst
    eine echte Kehre die volle Richtungsänderung in EINEM Fenster.
    """
    if len(coords) < 3:
        return []
    meter_points = _resample(coords, step_m=25.0)
    if len(meter_points) < 3:
        return []

    def heading(ax: float, ay: float, bx: float, by: float) -> float:
        return math.degrees(math.atan2(bx - ax, by - ay)) % 360.0

    segments: list[dict[str, float | str]] = []
    for i in range(1, len(meter_points) - 1):
        p0, p1, p2 = meter_points[i - 1], meter_points[i], meter_points[i + 1]
        chord = math.hypot(p2[0] - p0[0], p2[1] - p0[1])
        h1 = heading(p0[0], p0[1], p1[0], p1[1])
        h2 = heading(p1[0], p1[1], p2[0], p2[1])
        delta = _wrap_degrees(h2 - h1)
        radius = estimate_radius(chord, delta)
        if radius is None:
            weight = _STRAIGHT_WEIGHT
            cls: str = "straight"
        else:
            weight = _class_weight(radius)
            if radius < _CLASS_BOUNDS[0][0]:
                cls = "hairpin"
            elif radius < _CLASS_BOUNDS[1][0]:
                cls = "sharp"
            elif radius < _CLASS_BOUNDS[2][0]:
                cls = "medium"
            else:
                cls = "wide"
        # Länge des Fensters = Summe der zwei angrenzenden Segmente (Führungs-
        # anteil), nicht die Sehne selbst — sonst bleibt Kurvenzahl relativ
        # zur Gesamtstrecke realistisch.
        window_length = (
            math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            + math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        )
        segments.append(
            {
                "radius_m": radius if radius is not None else float("inf"),
                "length_m": window_length,
                "weight": weight,
                "class": cls,
            }
        )
    return segments


def curve_score(segments: list[dict[str, Any]], length_m_total: float) -> float:
    """Normierter Score 0–10: gewichtete Kurvenbeiträge pro Kilometer.

    Live-Kalibrierung (2026-10-11, Valhalla 3.9.1, Bayern-Tiles):
    Kesselberg 32,9 km → 7,7; Sudelfeld 26,9 km → 6,4;
    Autobahn A8 (67 km / 172 km) → 0,7 / 1,6. 'straight'-Fenster zählen
    bewusst Null — sonst würde die A8-Ulm-MUC-Route (1554 straight-
    Fenster) auf 3+ inflatiert werden.
    """
    if length_m_total <= 0:
        return 0.0
    total: float = sum(
        float(segment["weight"]) * float(segment["length_m"]) for segment in segments
    )
    score = (total / length_m_total) * _NORM_K
    return round(min(max(score, 0.0), _CLAMP_MAX), 2)


def count_enclosed_sharp_curves(
    segments: list[dict[str, Any]], radius_cap: float = _ANNOUNCE_MAX_RADIUS
) -> int:
    """Anzahl enger Kehren/Kurven (für TTS-Ansage, M4-kompatibel)."""
    return sum(
        1
        for segment in segments
        if segment.get("class") in ("hairpin", "sharp")
        and segment["radius_m"] <= radius_cap
    )
