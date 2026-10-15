import OpenAI from 'openai';

import { AIProvider } from './provider';

/**
 * OpenAI implementation of [AIProvider]. Uses Chat Completions with
 * `response_format: { type: 'json_object' }` so the model returns valid
 * JSON; we still JSON.parse and throw on malformed output.
 *
 * Model is a per-feature default (e.g. `gpt-4o-mini` for chat,
 * `gpt-4o` for vision). API key is read from `process.env.OPENAI_API_KEY`
 * which is bound at the callable level via `defineSecret('OPENAI_API_KEY')`.
 */
export class OpenAIClient implements AIProvider {
  constructor(private readonly model: string) {
    this._client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }

  private readonly _client: OpenAI;

  async generateJson(opts: {
    system: string;
    user: string;
  }): Promise<unknown> {
    const resp = await this._client.chat.completions.create({
      model: this.model,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: opts.system },
        { role: 'user', content: opts.user },
      ],
    });
    const text = resp.choices[0]?.message?.content ?? '';
    return _parseJson(text);
  }

  async generateJsonWithImage(opts: {
    system: string;
    user: string;
    imageUrl: string;
  }): Promise<unknown> {
    const resp = await this._client.chat.completions.create({
      model: this.model,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: opts.system },
        {
          role: 'user',
          content: [
            { type: 'text', text: opts.user },
            { type: 'image_url', image_url: { url: opts.imageUrl } },
          ],
        },
      ],
    });
    const text = resp.choices[0]?.message?.content ?? '';
    return _parseJson(text);
  }
}

function _parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error('AIProvider: invalid JSON response from OpenAI');
  }
}
