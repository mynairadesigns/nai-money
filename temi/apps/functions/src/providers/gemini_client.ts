import { GoogleGenerativeAI } from '@google/generative-ai';

import { AIProvider } from './provider';

/**
 * Gemini implementation of [AIProvider]. Uses
 * `responseMimeType: 'application/json'` so the model returns valid JSON;
 * we still JSON.parse and throw on malformed output.
 *
 * For images we fetch the bytes server-side (Node 22 built-in `fetch`)
 * and inline them as base64 — works for any public Firebase Storage URL
 * without needing the `fileData` URI scheme.
 *
 * Model is a per-feature default (see `models.ts`). API key is read from
 * `process.env.GEMINI_API_KEY` (bound via `defineSecret`).
 */
export class GeminiClient implements AIProvider {
  constructor(private readonly modelName: string) {
    const apiKey = process.env.GEMINI_API_KEY ?? '';
    this._sdk = new GoogleGenerativeAI(apiKey);
  }

  private readonly _sdk: GoogleGenerativeAI;

  async generateJson(opts: {
    system: string;
    user: string;
  }): Promise<unknown> {
    const model = this._sdk.getGenerativeModel({
      model: this.modelName,
      generationConfig: { responseMimeType: 'application/json' },
    });
    const resp = await model.generateContent({
      contents: [
        {
          role: 'user',
          parts: [{ text: `${opts.system}\n\n${opts.user}` }],
        },
      ],
    });
    const text = resp.response.text();
    return _parseJson(text);
  }

  async generateJsonWithImage(opts: {
    system: string;
    user: string;
    imageUrl: string;
  }): Promise<unknown> {
    const model = this._sdk.getGenerativeModel({
      model: this.modelName,
      generationConfig: { responseMimeType: 'application/json' },
    });
    const imgResp = await fetch(opts.imageUrl);
    if (!imgResp.ok) {
      throw new Error(
        `AIProvider: failed to fetch image (${imgResp.status} ${imgResp.statusText})`,
      );
    }
    const mimeType = imgResp.headers.get('content-type') ?? 'image/jpeg';
    const buf = await imgResp.arrayBuffer();
    const base64 = Buffer.from(buf).toString('base64');
    const resp = await model.generateContent({
      contents: [
        {
          role: 'user',
          parts: [
            { text: `${opts.system}\n\n${opts.user}` },
            { inlineData: { mimeType, data: base64 } },
          ],
        },
      ],
    });
    const text = resp.response.text();
    return _parseJson(text);
  }
}

function _parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error('AIProvider: invalid JSON response from Gemini');
  }
}
