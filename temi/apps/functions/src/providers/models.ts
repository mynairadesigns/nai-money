/**
 * Gemini model names in one place.
 *
 * Google retires model versions for new projects (the seller's
 * `gemini-2.5-flash-lite` / `gemini-2.5-flash` return 404 "no longer
 * available to new users"). Override without a code change by setting
 * GEMINI_MODEL_FAST / GEMINI_MODEL_VISION in apps/functions/.env (the
 * deploy workflow writes these from GitHub repo variables).
 */
export const GEMINI_FAST = process.env.GEMINI_MODEL_FAST || 'gemini-3.5-flash-lite';
export const GEMINI_VISION = process.env.GEMINI_MODEL_VISION || 'gemini-3.5-flash';
