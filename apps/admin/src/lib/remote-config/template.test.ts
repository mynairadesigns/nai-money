import type {
  RemoteConfigParameter,
  RemoteConfigTemplate,
} from 'firebase-admin/remote-config';
import { describe, expect, it } from 'vitest';

import { toLiveView } from './template';

/**
 * Only `toLiveView` is unit-tested here. It is the translation layer that
 * decides what the drift engine — and therefore the operator — believes the
 * server can see, so its handling of the non-explicit `defaultValue` variants
 * is worth pinning. `publishValues` needs a real Remote Config to mean
 * anything and belongs in the emulator-backed checks instead.
 */
function template(
  parameters: Record<string, RemoteConfigParameter>,
): RemoteConfigTemplate {
  return {
    conditions: [],
    parameters,
    parameterGroups: {},
    etag: 'etag-1',
  };
}

describe('toLiveView', () => {
  it('reads an explicit default value', () => {
    const view = toLiveView(
      template({ ai_provider: { defaultValue: { value: 'gemini' } } }),
    );

    expect(view.get('ai_provider')).toEqual({
      value: 'gemini',
      usesInAppDefault: false,
      hasConditionalValues: false,
      valueType: null,
    });
  });

  it('reports an in-app default as no value, because that is what the server sees', () => {
    const view = toLiveView(
      template({ ads_enabled: { defaultValue: { useInAppDefault: true } } }),
    );

    expect(view.get('ads_enabled')?.value).toBeNull();
    expect(view.get('ads_enabled')?.usesInAppDefault).toBe(true);
  });

  it('reports a rollout as no value, because the server cannot see one', () => {
    // The rollout's value is nested under `rolloutValue`, so the top-level
    // object has no `value` property — and select_provider.ts tests exactly
    // `'value' in defaultValue`. A parameter whose only default is a rollout is
    // therefore invisible to Cloud Functions.
    const view = toLiveView(
      template({
        ai_provider: {
          defaultValue: {
            rolloutValue: { rolloutId: 'r1', value: 'openai', percent: 50 },
          },
        },
      }),
    );

    expect(view.get('ai_provider')?.value).toBeNull();
    expect(view.get('ai_provider')?.usesInAppDefault).toBe(false);
  });

  it('detects conditional values only when there is at least one', () => {
    const view = toLiveView(
      template({
        with_conditions: {
          defaultValue: { value: 'a' },
          conditionalValues: { android: { value: 'b' } },
        },
        empty_conditions: {
          defaultValue: { value: 'a' },
          conditionalValues: {},
        },
      }),
    );

    expect(view.get('with_conditions')?.hasConditionalValues).toBe(true);
    expect(view.get('empty_conditions')?.hasConditionalValues).toBe(false);
  });

  it('carries the declared valueType through', () => {
    const view = toLiveView(
      template({
        free_tier_ai_quota: { defaultValue: { value: '5' }, valueType: 'NUMBER' },
      }),
    );

    expect(view.get('free_tier_ai_quota')?.valueType).toBe('NUMBER');
  });

  it('keeps a parameter that has no defaultValue at all', () => {
    // Condition-only parameters are legal. Dropping them would hide a key that
    // resolves to nothing server-side.
    const view = toLiveView(
      template({ odd: { conditionalValues: { ios: { value: 'x' } } } }),
    );

    expect(view.has('odd')).toBe(true);
    expect(view.get('odd')?.value).toBeNull();
  });

  it('returns an empty view for a template with no parameters', () => {
    expect(toLiveView(template({})).size).toBe(0);
  });
});
