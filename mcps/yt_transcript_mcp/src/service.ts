/**
 * YouTube Transcript fetcher — TypeScript port of youtube_transcript_api
 * Uses YouTube's InnerTube API to get authenticated transcript URLs.
 */

export interface TranscriptSegment {
  text: string;
  start: number;    // seconds
  duration: number; // seconds
}

interface CaptionTrack {
  baseUrl: string;
  languageCode: string;
  name: { simpleText: string };
  vssId: string;
  kind?: string;
}

/**
 * Extract video ID from a YouTube URL.
 * Supports: watch?v=, youtu.be/, /embed/, /shorts/
 */
export function extractVideoId(url: string): string {
  const patterns = [
    /(?:youtube\.com\/watch\?v=)([a-zA-Z0-9_-]{11})/,
    /(?:youtu\.be\/)([a-zA-Z0-9_-]{11})/,
    /(?:youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/,
    /(?:youtube\.com\/shorts\/)([a-zA-Z0-9_-]{11})/,
  ];

  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }

  // Plain video ID (11 chars)
  if (/^[a-zA-Z0-9_-]{11}$/.test(url)) return url;

  throw new Error(`Could not extract video ID from URL: ${url}`);
}

const USER_AGENT = 'Mozilla/5.0 (compatible; YouTubeTranscriptBot/1.0)';
const INNERTUBE_API_KEY = '***';
// YouTube returns captions for ANDROID client, not WEB (matches youtube_transcript_api Python lib)
const INNERTUBE_CONTEXT = {
  client: {
    clientName: 'ANDROID',
    clientVersion: '20.10.38',
  },
};

/**
 * Fetch caption tracks using YouTube's InnerTube API (/youtubei/v1/player).
 * This is the same approach used by the Python youtube_transcript_api.
 */
async function fetchCaptionTracks(videoId: string): Promise<CaptionTrack[]> {
  // Step 1: Fetch the video page to get a fresh API key
  const pageResponse = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
    headers: {
      'User-Agent': USER_AGENT,
      'Accept-Language': 'en-US,en;q=0.9',
    },
  });

  if (!pageResponse.ok) {
    throw new Error(`Failed to fetch video page: HTTP ${pageResponse.status}`);
  }

  const html = await pageResponse.text();

  // Extract innertube API key from the page
  const apiKeyMatch = html.match(/"INNERTUBE_API_KEY":"([^"]+)"/);
  const apiKey = apiKeyMatch?.[1] || INNERTUBE_API_KEY;

  // Step 2: POST to InnerTube player endpoint (ANDROID client for captions)
  const playerResponse = await fetch(
    `https://www.youtube.com/youtubei/v1/player?key=${apiKey}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': USER_AGENT,
        'Accept-Language': 'en-US,en;q=0.9',
      },
      body: JSON.stringify({
        context: INNERTUBE_CONTEXT,
        videoId,
      }),
    }
  );

  if (!playerResponse.ok) {
    throw new Error(`InnerTube API returned HTTP ${playerResponse.status}`);
  }

  const playerData = await playerResponse.json() as any;

  if (playerData.playabilityStatus?.status === 'ERROR') {
    const reason = playerData.playabilityStatus?.reason || 'Unknown error';
    throw new Error(`Video unavailable: ${reason}`);
  }

  const captions = playerData?.captions?.playerCaptionsTracklistRenderer?.captionTracks;

  if (!captions || captions.length === 0) {
    throw new Error('No captions available for this video.');
  }

  return captions as CaptionTrack[];
}

/**
 * Select the best caption track for the given language preference.
 * Priority: manual captions in preferred language > auto-generated in preferred language > any.
 */
function selectBestTrack(tracks: CaptionTrack[], language?: string): CaptionTrack {
  const lang = (language || 'en').toLowerCase();

  // 1. Try manual captions in the preferred language
  const manual = tracks.find(
    (t) => t.languageCode?.toLowerCase() === lang && t.kind !== 'asr'
  );
  if (manual) return manual;

  // 2. Try auto-generated in the preferred language
  const asr = tracks.find(
    (t) => t.languageCode?.toLowerCase() === lang
  );
  if (asr) return asr;

  // 3. Fallback: first available
  return tracks[0];
}

/**
 * Decode HTML entities from the XML transcript.
 */
function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\\n/g, ' ')
    .replace(/\n/g, ' ')
    .trim();
}

/**
 * Parse the XML transcript into an array of segments.
 * Handles:
 *  - ANDROID format: <p t="ms" d="ms"><s>word</s><s>word</s></p>
 *  - WEB format: <text start="s" dur="s">text</text>
 */
function parseTranscriptXml(xml: string): TranscriptSegment[] {
  const segments: TranscriptSegment[] = [];

  // ANDROID format: <p t="ms" d="ms">...<s>word</s>...</p>
  // Need to match whole <p>...</p> blocks to extract inner <s> text
  const pBlockRegex = /<p\s[^>]*?\bt="(\d+)"\s[^>]*?\bd="(\d+)"([^>]*)>([\s\S]*?)<\/p>/g;
  let pMatch;

  while ((pMatch = pBlockRegex.exec(xml)) !== null) {
    const startMs = parseInt(pMatch[1]);
    const durationMs = parseInt(pMatch[2]);
    const attrs = pMatch[3];
    const innerXml = pMatch[4];

    // Skip line-break paragraphs (a="1")
    if (/a="1"/.test(attrs)) continue;

    // Try extracting text from <s> tags (complex format)
    const sMatches = innerXml.matchAll(/<s[^>]*>([^<]*)<\/s>/g);
    const words: string[] = [];
    for (const sMatch of sMatches) {
      const word = decodeHtmlEntities(sMatch[1]).trim();
      if (word) words.push(word);
    }

    // Fallback: plain text inside <p> (simple format — no <s> children)
    const text = words.length > 0
      ? words.join(' ')
      : decodeHtmlEntities(innerXml.replace(/<[^>]+>/g, '').trim());

    if (text) {
      segments.push({
        start: startMs / 1000,     // ms → s
        duration: durationMs / 1000,
        text,
      });
    }
  }

  if (segments.length > 0) return segments;

  // WEB format fallback: <text start="s" dur="s">text</text>
  const webMatches = xml.matchAll(
    /<text start="([\d.]+)" dur="([\d.]+)"[^>]*>([^<]*)<\/text>/g
  );

  for (const match of webMatches) {
    segments.push({
      start: parseFloat(match[1]),
      duration: parseFloat(match[2]),
      text: decodeHtmlEntities(match[3]),
    });
  }

  return segments;
}

/**
 * Fetch YouTube video transcript.
 *
 * Uses YouTube's InnerTube API to get authenticated caption URLs,
 * then fetches and parses the XML transcript.
 *
 * @param urlOrId - Full YouTube URL or video ID
 * @param language - Preferred language code (default: 'en')
 * @returns Array of transcript segments with text, start time, and duration
 */
export async function getTranscript(
  urlOrId: string,
  language?: string
): Promise<TranscriptSegment[]> {
  const videoId = extractVideoId(urlOrId);

  const tracks = await fetchCaptionTracks(videoId);
  const track = selectBestTrack(tracks, language);

  // Fetch the transcript XML using the authenticated URL from InnerTube
  const response = await fetch(track.baseUrl, {
    headers: {
      'User-Agent': USER_AGENT,
      'Accept-Language': 'en-US,en;q=0.9',
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch transcript: HTTP ${response.status}`);
  }

  const xml = await response.text();

  if (!xml || xml.trim().length === 0) {
    throw new Error(`Transcript is empty. The video may require a proof-of-origin token (po_token).`);
  }

  const segments = parseTranscriptXml(xml);

  if (segments.length === 0) {
    throw new Error('Failed to parse transcript XML.');
  }

  return segments;
}

/**
 * Get transcript as plain text (all segments joined).
 */
export async function getTranscriptText(
  urlOrId: string,
  language?: string
): Promise<string> {
  const segments = await getTranscript(urlOrId, language);
  return segments.map((s) => s.text).join(' ');
}

/**
 * Search for text within a transcript.
 */
export async function searchTranscript(
  urlOrId: string,
  query: string,
  options?: { language?: string; contextWindow?: number; caseSensitive?: boolean }
): Promise<{ segment: TranscriptSegment; contextBefore: string; contextAfter: string }[]> {
  const segments = await getTranscript(urlOrId, options?.language);
  const window = options?.contextWindow ?? 1; // segments before/after
  const caseSensitive = options?.caseSensitive ?? false;
  const searchQuery = caseSensitive ? query : query.toLowerCase();

  const results: { segment: TranscriptSegment; contextBefore: string; contextAfter: string }[] = [];

  for (let i = 0; i < segments.length; i++) {
    const text = caseSensitive ? segments[i].text : segments[i].text.toLowerCase();
    if (text.includes(searchQuery)) {
      const before = segments.slice(Math.max(0, i - window), i).map((s) => s.text).join(' ');
      const after = segments.slice(i + 1, i + 1 + window).map((s) => s.text).join(' ');
      results.push({ segment: segments[i], contextBefore: before, contextAfter: after });
    }
  }

  return results;
}
