import { Card, CardTitle } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import {
  FEATURE_PROFILES,
  MODEL_PRICES,
  modelForFeature,
  type AiFeature,
  type ProviderSetting,
} from '@/lib/cost/estimate';
import { formatNumber } from '@/lib/format';

/**
 * The full derivation behind every dollar figure on this page.
 *
 * Shown rather than hidden in code comments because the estimate is only
 * defensible if an operator can audit it: the counters record calls, so the
 * token assumptions are the entire difference between a call count and a cost,
 * and a reader who disagrees with one needs to see it to discount the number.
 */
export function Assumptions({ setting }: { setting: ProviderSetting }) {
  const features = Object.keys(FEATURE_PROFILES) as AiFeature[];

  return (
    <Card className="flex flex-col gap-6">
      <div>
        <CardTitle>How the estimate is built</CardTitle>
        <p className="mt-2 max-w-prose text-body-md text-on-surface-variant">
          Nothing in Temi Finance records tokens — the counters record calls. Cost
          is therefore calls x an assumed prompt and response size x the
          model&rsquo;s list price. Batch, cached-input, and committed-use
          discounts are ignored, so these figures are a list-price ceiling and
          will not reconcile with a provider invoice.
        </p>
      </div>

      <div>
        <h3 className="text-label-md uppercase text-on-surface-variant">
          Per-feature assumptions
        </h3>
        <Table>
          <THead>
            <TH>Feature</TH>
            <TH>Model in use</TH>
            <TH numeric>Input tokens</TH>
            <TH numeric>Output tokens</TH>
            <TH>Basis</TH>
          </THead>
          <TBody>
            {features.map((feature) => {
              const profile = FEATURE_PROFILES[feature];
              return (
                <TR key={feature}>
                  <TD>{profile.label}</TD>
                  <TD className="whitespace-nowrap text-on-surface-variant">
                    {modelForFeature(feature, setting)}
                  </TD>
                  <TD numeric>{formatNumber(profile.inputTokens)}</TD>
                  <TD numeric>{formatNumber(profile.outputTokens)}</TD>
                  <TD className="text-on-surface-variant">{profile.basis}</TD>
                </TR>
              );
            })}
          </TBody>
        </Table>
      </div>

      <div>
        <h3 className="text-label-md uppercase text-on-surface-variant">
          Model prices &middot; USD per 1M tokens
        </h3>
        <Table>
          <THead>
            <TH>Model</TH>
            <TH numeric>Input</TH>
            <TH numeric>Output</TH>
          </THead>
          <TBody>
            {Object.entries(MODEL_PRICES).map(([model, price]) => (
              <TR key={model}>
                <TD>{model}</TD>
                <TD numeric>${price.inputPerMillion.toFixed(2)}</TD>
                <TD numeric>${price.outputPerMillion.toFixed(2)}</TD>
              </TR>
            ))}
          </TBody>
        </Table>
        <p className="mt-2 max-w-prose text-label-sm text-on-surface-variant">
          Transcribed from each provider&rsquo;s public pricing page, not fetched
          at runtime. Re-check them in{' '}
          <code>src/lib/cost/estimate.ts</code> when a provider announces a
          change — they go stale silently.
        </p>
      </div>
    </Card>
  );
}
