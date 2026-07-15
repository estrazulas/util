import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from 'zod/v3';
import { getTranscript, searchTranscript, getTranscriptText } from "./service.ts";

export const server = new McpServer({
    name: '@estrazulas/yt-transcript-mcp',
    version: '0.0.1'
});

server.registerTool(
    'get_transcript',
    {
        description: 'Extract transcript from a YouTube video. Returns segments with text, start time (seconds), and duration.',
        inputSchema: {
            url: z.string().describe(
                "YouTube video URL (watch?v=, youtu.be, /embed/, /shorts/) or plain video ID"
            ),
            language: z.string().optional().describe(
                "Preferred language code (e.g., 'pt', 'en'). Auto-detects if omitted."
            ),
        },
        outputSchema: {
            transcript: z.array(z.object({
                text: z.string(),
                start: z.number(),
                duration: z.number(),
            })),
            language: z.string(),
            segmentCount: z.number(),
        }
    },
    async ({ url, language }) => {
        try {
            const segments = await getTranscript(url, language);
            return {
                content: [{
                    type: "text",
                    text: segments.map(s => `[${s.start.toFixed(1)}s] ${s.text}`).join('\n')
                }],
                structuredContent: {
                    transcript: segments,
                    segmentCount: segments.length,
                    language: language || 'auto-detected',
                }
            };
        } catch (error) {
            return {
                isError: true,
                content: [{
                    type: 'text',
                    text: `Failed to get transcript: ${error instanceof Error ? error.message : String(error)}`
                }]
            };
        }
    }
);

server.registerTool(
    'search_transcript',
    {
        description: 'Search for text within a YouTube video transcript. Returns matching segments with surrounding context.',
        inputSchema: {
            url: z.string().describe("YouTube video URL or video ID"),
            query: z.string().describe("Text to search for in the transcript"),
            contextWindow: z.number().optional().describe(
                "Number of segments of context before and after each match (default: 1)"
            ),
            caseSensitive: z.boolean().optional().describe(
                "Case-sensitive search (default: false)"
            ),
            language: z.string().optional().describe(
                "Preferred language code"
            ),
        },
    },
    async ({ url, query, contextWindow, caseSensitive, language }) => {
        try {
            const results = await searchTranscript(url, query, {
                language,
                contextWindow,
                caseSensitive,
            });

            if (results.length === 0) {
                return {
                    content: [{ type: "text", text: `No matches found for "${query}".` }],
                    structuredContent: { matches: [], count: 0 }
                };
            }

            const formatted = results.map((r, i) => {
                const contextStr = [];
                if (r.contextBefore) contextStr.push(`...${r.contextBefore}`);
                contextStr.push(`>>> [${r.segment.start.toFixed(1)}s] ${r.segment.text} <<<`);
                if (r.contextAfter) contextStr.push(`${r.contextAfter}...`);
                return `Match ${i + 1}:\n${contextStr.join('\n')}`;
            }).join('\n\n');

            return {
                content: [{ type: "text", text: formatted }],
                structuredContent: {
                    matches: results.map(r => ({
                        timestamp: r.segment.start,
                        text: r.segment.text,
                        contextBefore: r.contextBefore,
                        contextAfter: r.contextAfter,
                    })),
                    count: results.length,
                }
            };
        } catch (error) {
            return {
                isError: true,
                content: [{
                    type: 'text',
                    text: `Search failed: ${error instanceof Error ? error.message : String(error)}`
                }]
            };
        }
    }
);

server.registerTool(
    'get_transcript_text',
    {
        description: 'Get YouTube video transcript as a single plain-text string.',
        inputSchema: {
            url: z.string().describe("YouTube video URL or video ID"),
            language: z.string().optional().describe("Preferred language code"),
        },
        outputSchema: {
            text: z.string(),
            segmentCount: z.number(),
        }
    },
    async ({ url, language }) => {
        try {
            const [text, segments] = await Promise.all([
                getTranscriptText(url, language),
                getTranscript(url, language),
            ]);
            return {
                content: [{ type: "text", text }],
                structuredContent: { text, segmentCount: segments.length }
            };
        } catch (error) {
            return {
                isError: true,
                content: [{
                    type: 'text',
                    text: `Failed to get transcript: ${error instanceof Error ? error.message : String(error)}`
                }]
            };
        }
    }
);

server.registerResource(
    'transcript://info',
    'transcript://info',
    {
        description: 'Describes how the YouTube transcript extraction works and supported URL formats',
    },
    () => ({
        contents: [
            {
                uri: "transcript://info",
                mimeType: "text/plain",
                text: `
YouTube Transcript MCP Server
==============================
Extracts transcripts/captions from YouTube videos using YouTube's internal API.
No API key required.

Supported URL formats:
  - https://www.youtube.com/watch?v=VIDEO_ID
  - https://youtu.be/VIDEO_ID
  - https://www.youtube.com/embed/VIDEO_ID
  - https://www.youtube.com/shorts/VIDEO_ID
  - Plain video ID (11 characters)

Available tools:
  - get_transcript: Returns array of {text, start, duration}
  - get_transcript_text: Returns plain text string
  - search_transcript: Search with context windows

How it works:
  1. Fetches the YouTube video page HTML
  2. Extracts caption track URLs from ytInitialPlayerResponse
  3. Selects best track by language preference (manual > auto-generated)
  4. Fetches and parses the XML transcript
                `.trim(),
            },
        ]
    })
);
