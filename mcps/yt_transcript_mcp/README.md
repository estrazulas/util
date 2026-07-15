# @estrazulas/yt-transcript-mcp

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that extracts transcripts from YouTube videos using YouTube's internal API. No API key required — a TypeScript port of [youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api).

---

## How it works (for LLMs)

When an AI agent needs to understand a YouTube video's content, it calls this MCP server instead of watching the video or reading an unreliable summary. Here's the internal flow:

```
LLM receives user prompt:
  "What does the video https://youtu.be/nQdxsjaeLSk say about Graphify?"

LLM decides to call:
  search_transcript(url="https://youtu.be/nQdxsjaeLSk", query="Graphify")

MCP server internally:
  1. Extracts video ID from the URL → "nQdxsjaeLSk"
  2. Fetches the YouTube watch page HTML
  3. Extracts YouTube's public InnerTube API key from the page
  4. POSTs to youtubei/v1/player as ANDROID client (only mobile client returns captions)
  5. Parses the JSON response to get authenticated caption track URLs
  6. Fetches the XML caption data using the authenticated URL
  7. Parses XML <p> tags (both simple and word-level <s> formats) into segments
  8. Searches segments for "Graphify" with context windows
  9. Returns matching segments with timestamps and surrounding context

LLM receives:
  - Exact transcript text with timestamps
  - Context around each match
  - Can now answer the user's question with precise quotes
```

### Why InnerTube API?

YouTube's official Data API v3 requires OAuth 2.0 for caption downloads. This server uses the same endpoint the YouTube Android app uses (`youtubei/v1/player`), which returns authenticated caption URLs that work without any API key from the developer.

---

## What it does

| Tool | Description |
|------|-------------|
| `get_transcript` | Extract full transcript as timed segments |
| `get_transcript_text` | Extract transcript as a single plain-text string |
| `search_transcript` | Search for text within a video transcript with context windows |

| Resource | Description |
|----------|-------------|
| `transcript://info` | Server info and supported URL formats |

---

## Tools

### `get_transcript`

Extract transcript from a single YouTube video. Returns an array of segments, each with text, start time (seconds), and duration.

**Parameters:**
- `url` (required) — YouTube video URL or video ID
- `language` (optional) — Language code (`'en'`, `'pt'`, `'es'`, etc.). Auto-detects if omitted.

**Returns:** Array of `{ text, start, duration }` segments.

**Example LLM usage:**
```
User: "Transcribe this video: https://youtu.be/nQdxsjaeLSk"

LLM calls get_transcript(url="https://youtu.be/nQdxsjaeLSk", language="en")
→ Returns 319 segments with timestamps
→ LLM summarizes: "The video introduces Graphify, a tool that turns codebases into knowledge graphs..."
```

---

### `get_transcript_text`

Same as `get_transcript` but returns a single concatenated string — useful when the LLM needs the full text for summarization or embedding.

**Parameters:**
- `url` (required)
- `language` (optional)

**Returns:** Single string with all transcript text joined by spaces.

**Example LLM usage:**
```
LLM calls get_transcript_text(url="nQdxsjaeLSk")
→ Returns ~12000 character plain-text string
→ LLM uses it as context for a detailed analysis or summary
```

---

### `search_transcript`

Search for specific text within a transcript. Returns matching segments with surrounding context — ideal for fact-checking or finding where a topic is discussed.

**Parameters:**
- `url` (required) — YouTube video URL or ID
- `query` (required) — Text to search for
- `contextWindow` (optional) — Number of segments before/after each match (default: 1)
- `caseSensitive` (optional) — Case-sensitive search (default: false)
- `language` (optional) — Language code

**Returns:** Array of `{ timestamp, text, contextBefore, contextAfter }`.

**Example LLM usage:**
```
User: "Does this video mention Graphify? At what timestamp?"

LLM calls search_transcript(url="nQdxsjaeLSk", query="Graphify", language="en")
→ Returns 27 matches, first one at 32.54s: "Its name is Graphify."
→ LLM answers: "Yes, the name 'Graphify' is first mentioned at 0:32."
```

---

## Supported URL formats

- `https://www.youtube.com/watch?v=VIDEO_ID`
- `https://youtu.be/VIDEO_ID`
- `https://www.youtube.com/embed/VIDEO_ID`
- `https://www.youtube.com/shorts/VIDEO_ID`
- Plain video ID (11 characters): `nQdxsjaeLSk`

---

## Installation

```bash
npm install
```

No build step — runs TypeScript directly via Node.js native TypeScript support.

---

## Using with Hermes Agent

Add to your Hermes MCP configuration:

```bash
hermes mcp add youtube-transcript --command node --args "--experimental-strip-types /home/estrazulas/git/utils/mcps/yt_transcript_mcp/src/index.ts"
```

Or manually in `~/.hermes/config.yaml` under `mcp_servers`:

```yaml
mcp_servers:
  youtube-transcript:
    command: node
    args:
      - "--experimental-strip-types"
      - "/home/estrazulas/git/utils/mcps/yt_transcript_mcp/src/index.ts"
    transport: stdio
```

---

## Using in VS Code

Create `.vscode/mcp.json` in your workspace:

```json
{
  "servers": {
    "yt-transcript": {
      "command": "node",
      "args": [
        "--experimental-strip-types",
        "/home/estrazulas/git/utils/mcps/yt_transcript_mcp/src/index.ts"
      ]
    }
  }
}
```

---

## Running the MCP Inspector

```bash
npm run mcp:inspect
```

Opens the MCP Inspector at `http://localhost:5173` — explore and test all tools interactively.

---

## Running tests

```bash
npm test          # Run all tests once
npm run test:dev  # Watch mode with debugger
```

The test suite covers:
- Extracting transcript from a video (full URL, short URL, plain ID)
- Getting plain text transcript
- Searching within transcript
- Structured data validation (timestamps, segment count)
- Error handling for invalid videos

---

## Project structure

```
src/
  index.ts    # Entry point — stdio transport
  mcp.ts      # Tool registration (get_transcript, search_transcript, etc.)
  service.ts  # Core logic — InnerTube API, XML parsing, URL extraction
tests/
  helpers.ts  # MCP test client factory
  mcp.test.ts # Integration tests with real YouTube videos
```

---

## Scripts

| Script | Description |
|--------|-------------|
| `npm start` | Start the MCP server |
| `npm run dev` | Start with file-watch and debugger |
| `npm test` | Run all tests |
| `npm run test:dev` | Run tests in watch mode |
| `npm run mcp:inspect` | Open MCP Inspector UI |
