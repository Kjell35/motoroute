import { AvoidOption } from './dto/create-route.dto';

/**
 * Builds a request-time custom_model fragment that GraphHopper merges
 * on top of the chosen profile's own custom_model files. This is what
 * lets "Autobahn vermeiden" apply on top of ANY fahrstil (including
 * curvy ones) without duplicating the avoid-logic into every
 * style_*.json file - see Phase 1/2, Abschnitt 5: an avoid option must
 * survive a reroute regardless of which style is active.
 *
 * multiply_by "0" is used instead of a road-block/exclude mechanism so
 * that a route is still returned even if strictly avoiding is
 * technically impossible (e.g. a ferry is the only connection) rather
 * than the request failing outright - GraphHopper will simply pay a
 * very high cost for using it. Whether that's the right trade-off for
 * "hard avoid" vs. "strong preference" is a product decision worth
 * revisiting once real users hit that edge case.
 */
export function buildAvoidPriorityRules(avoid: AvoidOption[] = []): Array<Record<string, string>> {
  const rules: Array<Record<string, string>> = [];

  if (avoid.includes(AvoidOption.HIGHWAY)) {
    rules.push({ if: 'road_class == MOTORWAY', multiply_by: '0.02' });
  }
  if (avoid.includes(AvoidOption.FERRY)) {
    rules.push({ if: 'road_environment == FERRY', multiply_by: '0.02' });
  }
  if (avoid.includes(AvoidOption.TOLL)) {
    rules.push({ if: 'toll != NO', multiply_by: '0.02' });
  }

  return rules;
}
