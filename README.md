# 🌿 OutThere

**Meet people in Cairo by doing things together outside: small games, language circles, walks and treasure hunts in public parks.**

OutThere is a lightweight web app for finding and hosting small group activities in public outdoor spaces. Its AI Idea Lab uses **Gemma**, an open-weight model, to plan an activity that fits your group, time, area and budget. By default Gemma runs **entirely in your browser** through [WebLLM](https://github.com/mlc-ai/web-llm), so your interests and neighborhood never leave your device.

Built for the [Hacktoberfest Open-Source AI Challenge, Week 1: Touch Grass](https://dev.to/challenges/hacktoberfest-week1-2026-10-05).

## Features

- **Explore** activities by category, neighborhood, group size and date.
- **Join and leave** with rules enforced: sign-in required, no duplicate joins, capacity limits, no joining cancelled or finished activities.
- **Host** an activity with validation (future start time, 2–30 people, 15–480 minutes).
- **Transparent recommendations**: each card says why it matches you (category +3, neighborhood +2, interests +1, group size +1). No hidden scoring.
- **AI Idea Lab**: Gemma writes a full plan (steps, conversation prompts, variations, accessibility notes, safety checks, closing reflection) plus one sentence on why it fits you. Output is validated, and fixed safety rules are always appended.
- **Honest data**: seed activities are tagged as demo data, venues are marked unverified, and the AI is told never to invent venue names, opening hours, fees or crowd levels. Venue pages link to an OpenStreetMap search instead of claiming coordinates.
- **Safety**: community guidelines and a report button on every activity.

## The AI, and why it's open

| Mode | Model | Where it runs | Data leaves device? |
|---|---|---|---|
| On-device (default) | `gemma-2-2b-it` (q4f16 or q4f32, picked from your GPU) | Your browser, via WebGPU | No |
| Hosted fallback (when WebGPU is missing) | `gemma-4-26b-a4b-it` on Google AI Studio, via a Supabase Edge Function | Google's servers | Yes, and the app says so |
| Self-hosted | Any model on Ollama / vLLM, e.g. `gemma3:4b` | Your own machine or server | Only to a server you control |
| Fallback | Curated template | Your browser | No, and it is labelled "not AI-generated" |

Every plan shows which of these produced it.

## Run it

It is one static file, `index.html`. Serve it over HTTPS or `localhost` (WebGPU needs a secure context):

```bash
python3 -m http.server 8000   # then open http://localhost:8000
```

On-device AI needs a browser with WebGPU (recent Chrome or Edge on desktop, Chrome on newer Android). The first run downloads about 1.5 GB of model weights, which the browser caches.

### Use Ollama instead

```bash
OLLAMA_ORIGINS=* ollama serve
ollama pull gemma3:4b
```

In the Idea Lab, open **Model settings**, choose *Ollama / OpenAI-compatible endpoint*, set the URL to `http://localhost:11434/v1` and the model to `gemma3:4b`.

### Deploy

GitHub Pages or a Render Static Site: point it at the repo root, no build command, publish directory `.`.

### Hosted fallback

`supabase/functions/gemma-plan` keeps the Google AI Studio key server-side, builds the prompt itself from validated form fields (so it can't be used as a general chatbot), only accepts requests from the app's own origin, and rate-limits per IP. Set the `GEMINI_API_KEY` secret, deploy with JWT verification off, and put the function URL in `HOSTED_URL` near the bottom of `index.html`.

## Current limits

- Accounts and activities are stored in `localStorage` (demo mode). Don't use a real password.
- Venues are unverified demo records.

## Optional backend (`/supabase`)

A Supabase schema and Edge Function are included for multi-user mode. They are **not yet wired into the frontend**.

- `schema.sql`: tables, Row Level Security, an atomic `join_activity` function that locks the row so capacity can't be exceeded under concurrent joins, a unique constraint against duplicate joins, and a public view of participant counts that doesn't reveal who joined.
- `functions/idea-lab`: server-side generation with any OpenAI-compatible open-weight endpoint (for example Gemma on Hugging Face Inference Providers), with per-user rate limiting and output validation.

## Tech

Vanilla HTML/CSS/JS · WebLLM · Gemma · optional Supabase (Postgres + RLS + Deno Edge Functions)

## License

MIT
