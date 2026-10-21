# 0002 Readiness without a Garmin sleep score

Status: accepted, 21 Oct 2026 (WBS 2.7). Implemented in `packages/coach_engine/lib/src/readiness.dart` (`estimateSleepScore`).

## Problem

Readiness weights its sleep axis at 0.35, and that axis is Garmin's 0-100 sleep score. Health Connect doesn't carry Garmin's score, and other watches don't produce one, so a phone with only Health Connect data would score readiness without sleep at all. Body battery and Garmin's HRV status are missing for the same reason. The engine already drops missing inputs and reweights the rest; sleep is the input worth replacing.

## Decision

When a night has no sleep score but does have its stage minutes, readiness estimates a 0-100 score from the night itself. The estimate is used exactly where Garmin's score would be: sub-score = score / 100, with the existing short-sleep guard (capped at 0.50 under 5 hours asleep) still applied.

It combines three sub-scores, each piecewise linear and flat beyond its end points, weighted and renormalized over the ones a night has data for:

| Input | Weight | Curve (input → sub-score) | Basis |
|---|---|---|---|
| Total sleep time, light + deep + REM minutes | 0.5 | 0 → 0, 5 h → 0.35, 6 h → 0.60, 7 h → 0.85, 8 h → 1.0 | Adults should sleep at least 7 hours (AASM and SRS consensus, Watson 2015); 7 to 9 hours recommended for ages 18 to 64 (NSF, Hirshkowitz 2015). Long nights aren't penalized, since athletes often need more (Walsh 2021). |
| Sleep efficiency, time asleep over time in bed (needs the sleep start and end times) | 0.3 | 65% → 0.20, 75% → 0.50, 85% → 0.85, 90% → 1.0 | 85% or more indicates good sleep quality, 74% or less poor (NSF sleep quality recommendations, Ohayon 2017). |
| Minutes awake after falling asleep | 0.2 | 20 → 1.0, 50 → 0.60, 90 → 0.30 | 20 minutes or less indicates good quality and 51 or more poor, for ages 26 to 64 (Ohayon 2017). |

An efficiency the times contradict (more sleep than 105% of the time in bed) is ignored rather than clamped.

Sleep stage proportions are left out. Wrist devices stage sleep poorly, and the NSF panel found no consensus on stage-based quality markers.

## How it shows

- The sleep component gets `estimated: true` and an `estimate` object holding the inputs and sub-scores.
- The flag `sleep_estimated` is added, and confidence drops one step: a night with HRV, resting HR and an estimated sleep score reads "medium", not "high".
- The briefing says "estimated sleep score" whenever sleep is a driver.
- Nights with a Garmin score are untouched, so the Dart engine still matches the Python one on every parity fixture.

## Limitations

- The estimate isn't calibrated against Garmin's score. An Android Garmin user whose history comes from a Garmin export (with Garmin's scores) and whose recent nights come from Health Connect (estimated) may see a step between the two. Once users have nights with both, fit the curves against those overlaps.
- Total sleep time and time awake depend on the watch's own sleep detection, which varies by device.
- The constants are judgment, anchored on the population thresholds above. They are at the top of `readiness.dart`, with the other readiness constants, for retuning.

## Sources

- Watson NF et al. Recommended amount of sleep for a healthy adult: a joint consensus statement of the American Academy of Sleep Medicine and Sleep Research Society. Sleep. 2015;38(6):843-844.
- Hirshkowitz M et al. National Sleep Foundation's sleep time duration recommendations: methodology and results summary. Sleep Health. 2015;1(1):40-43.
- Ohayon M et al. National Sleep Foundation's sleep quality recommendations: first report. Sleep Health. 2017;3(1):6-19.
- Walsh NP et al. Sleep and the athlete: narrative review and 2021 expert consensus recommendations. Br J Sports Med. 2021;55(7):356-368.
