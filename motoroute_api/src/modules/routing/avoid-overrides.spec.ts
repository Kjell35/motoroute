import { AvoidOption } from './dto/create-route.dto';
import { buildAvoidPriorityRules } from './avoid-overrides';

describe('buildAvoidPriorityRules', () => {
  it('returns no rules when nothing is avoided', () => {
    expect(buildAvoidPriorityRules([])).toEqual([]);
    expect(buildAvoidPriorityRules(undefined)).toEqual([]);
  });

  it('adds a motorway de-prioritization rule for HIGHWAY', () => {
    const rules = buildAvoidPriorityRules([AvoidOption.HIGHWAY]);
    expect(rules).toContainEqual({ if: 'road_class == MOTORWAY', multiply_by: '0.02' });
  });

  it('combines multiple avoid options into independent rules', () => {
    const rules = buildAvoidPriorityRules([AvoidOption.FERRY, AvoidOption.TOLL]);
    expect(rules).toHaveLength(2);
    expect(rules).toContainEqual({ if: 'road_environment == FERRY', multiply_by: '0.02' });
    expect(rules).toContainEqual({ if: 'toll != NO', multiply_by: '0.02' });
  });

  it('never fully excludes a road, only de-prioritizes it, so a route is always possible', () => {
    const rules = buildAvoidPriorityRules([AvoidOption.HIGHWAY, AvoidOption.FERRY, AvoidOption.TOLL]);
    for (const rule of rules) {
      expect(Number(rule.multiply_by)).toBeGreaterThan(0);
    }
  });
});
