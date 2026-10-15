import { Badge } from '@/components/ui';
import { entitlementDrift, isPremiumNow, type UserListRow } from '@/lib/data/user-mapping';

/**
 * One badge that answers "what is this user's entitlement, really".
 *
 * Deliberately not a plain read of `premiumStatus`: that field alone is what
 * misleads operators. A lapsed or null-expiry document still says 'premium'
 * while the server denies the quota bypass, so the drift cases get their own
 * tones rather than being folded into "Premium".
 */
export function EntitlementBadge({
  row,
  nowMs,
}: {
  row: UserListRow;
  nowMs: number;
}) {
  const drift = entitlementDrift(row, nowMs);

  if (drift === 'expired-but-marked-premium') {
    return <Badge tone="critical">Lapsed premium</Badge>;
  }
  if (drift === 'free-but-has-future-expiry') {
    return <Badge tone="warning">Mirror drift</Badge>;
  }

  return isPremiumNow(row, nowMs) ? (
    <Badge tone="positive">Premium</Badge>
  ) : (
    <Badge tone="neutral">Free</Badge>
  );
}
