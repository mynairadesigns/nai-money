/**
 * Provider abstraction for AI calls — both OpenAI and Gemini implement
 * this interface so the rest of the codebase doesn't care which one is
 * active. Selection is per-call via {@link selectProvider} which reads
 * Remote Config (`ai_provider`) at runtime; per-feature defaults live
 * inside each callable.
 *
 * Both methods MUST return parsed JSON (i.e. JSON.parse the model's
 * response). Implementations throw if the model returns non-JSON.
 */
export interface AIProvider {
  /** Text-only — system + user → JSON. */
  generateJson(opts: { system: string; user: string }): Promise<unknown>;

  /** Vision — system + user + public image URL → JSON. */
  generateJsonWithImage(opts: {
    system: string;
    user: string;
    imageUrl: string;
  }): Promise<unknown>;
}
