// AI narrative provider chain.
//
// Replaces Cloudflare Workers AI (@cf/meta/llama-3.3-70b-instruct-fp8-fast).
// Providers are tried in order; a provider may signal that a given error is
// retryable on the NEXT provider (`shouldFallback`). Adding a third provider
// is just appending another `AIProvider` to `providers`.
//
//   Primary : Groq  — Llama 3.3 70B, OpenAI-compatible API
//   Fallback: Gemini — gemini-2.5-flash-lite
//
// PRIVACY: callers pass ONLY the abstracted weather summary (numeric values
// such as temperature, humidity, pressure, wind). No coordinates, IP, or any
// device/user identifier is ever sent to a provider. See util.buildWeatherSummary.

export interface AIProvider {
  readonly name: string;
  /** True when this provider is usable (e.g. its API key is configured). */
  isConfigured(): boolean;
  /** Generate the narrative text, or throw `AIProviderError` on failure. */
  generate(system: string, user: string): Promise<string>;
  /** Whether `err` should trigger a fallback to the next provider. */
  shouldFallback(err: unknown): boolean;
}

export class AIProviderError extends Error {
  constructor(
    readonly provider: string,
    readonly status: number | null,
    message: string,
  ) {
    super(message);
    this.name = "AIProviderError";
  }
}

const GROQ_BASE = "https://api.groq.com/openai/v1";
const GROQ_MODEL = "llama-3.3-70b-versatile";
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODEL = "gemini-2.5-flash-lite";
const MAX_TOKENS = 400;
const TIMEOUT_MS = 15000;

// --- Groq (primary) — OpenAI-compatible chat/completions -------------------

class GroqProvider implements AIProvider {
  readonly name = "groq";

  isConfigured(): boolean {
    return !!Deno.env.get("GROQ_API_KEY");
  }

  async generate(system: string, user: string): Promise<string> {
    const key = Deno.env.get("GROQ_API_KEY");
    if (!key) throw new AIProviderError(this.name, null, "GROQ_API_KEY not set");

    const res = await fetch(`${GROQ_BASE}/chat/completions`, {
      method: "POST",
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${key}`,
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        max_tokens: MAX_TOKENS,
      }),
    });

    if (!res.ok) {
      throw new AIProviderError(this.name, res.status, `Groq HTTP ${res.status}`);
    }
    const data = await res.json();
    const text = (data?.choices?.[0]?.message?.content ?? "").trim();
    if (!text) throw new AIProviderError(this.name, res.status, "Groq empty response");
    return text;
  }

  // Fall back to the next provider on rate limit (429), model-not-found (404),
  // or any server-side error (5xx) — Groq being down shouldn't deny the user a
  // narrative when Gemini is available.
  shouldFallback(err: unknown): boolean {
    if (err instanceof AIProviderError) {
      return err.status === null || err.status === 429 || err.status === 404 ||
        err.status >= 500;
    }
    return true; // network/timeout errors -> try the next provider
  }
}

// --- Gemini (fallback) ------------------------------------------------------

class GeminiProvider implements AIProvider {
  readonly name = "gemini";

  isConfigured(): boolean {
    return !!Deno.env.get("GEMINI_API_KEY");
  }

  async generate(system: string, user: string): Promise<string> {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new AIProviderError(this.name, null, "GEMINI_API_KEY not set");

    const res = await fetch(
      `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent`,
      {
        method: "POST",
        signal: AbortSignal.timeout(TIMEOUT_MS),
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: system }] },
          contents: [{ role: "user", parts: [{ text: user }] }],
          generationConfig: { maxOutputTokens: MAX_TOKENS },
        }),
      },
    );

    if (!res.ok) {
      throw new AIProviderError(this.name, res.status, `Gemini HTTP ${res.status}`);
    }
    const data = await res.json();
    const text = (data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "").trim();
    if (!text) throw new AIProviderError(this.name, res.status, "Gemini empty response");
    return text;
  }

  shouldFallback(err: unknown): boolean {
    if (err instanceof AIProviderError) {
      return err.status === 429 || err.status === 404 || err.status === null;
    }
    return true;
  }
}

// Ordered provider chain. Append here to add a third provider.
const providers: AIProvider[] = [new GroqProvider(), new GeminiProvider()];

/** True when at least one provider is configured (has an API key). */
export function anyProviderConfigured(): boolean {
  return providers.some((p) => p.isConfigured());
}

/**
 * Run the provider chain. Returns the first successful narrative. Throws when
 * every configured provider fails (caller should fall back to a static string).
 */
export async function generateNarrative(system: string, user: string): Promise<string> {
  let lastErr: unknown = new Error("no AI provider configured");
  for (const p of providers) {
    if (!p.isConfigured()) continue;
    try {
      return await p.generate(system, user);
    } catch (err) {
      lastErr = err;
      console.warn(`AI provider '${p.name}' failed:`, err);
      if (p.shouldFallback(err)) continue;
      throw err;
    }
  }
  throw lastErr;
}
