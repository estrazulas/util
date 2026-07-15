import { describe, it, after, before } from 'node:test';
import assert from 'node:assert';
import { Client } from '@modelcontextprotocol/sdk/client';
import { createTestClient } from './helpers.ts';

const TEST_VIDEO_URL = 'https://www.youtube.com/watch?v=nQdxsjaeLSk';

describe('YouTube Transcript MCP Tool Tests', () => {
    let client: Client;

    before(async () => {
        client = await createTestClient();
    });

    after(async () => {
        await client.close();
    });

    it('should list the transcript://info resource', async () => {
        const { resources } = await client.listResources();
        const info = resources.find(item => item.uri === 'transcript://info');

        assert.ok(info, 'transcript://info resource should be listed');
    });

    it('should extract transcript from a YouTube video', async () => {
        const result = await client.callTool({
            name: 'get_transcript',
            arguments: {
                url: TEST_VIDEO_URL,
            }
        });

        const content = result.content as Array<{ type: string; text: string }>;
        const textOutput = content.find(c => c.type === 'text')?.text || '';

        assert.ok(textOutput.length > 100, 'Transcript should have meaningful content');
        assert.ok(
            textOutput.includes('[0.'),
            'Transcript should contain timestamp markers'
        );
    });

    it('should return structured data with transcript array', async () => {
        const result = await client.callTool({
            name: 'get_transcript',
            arguments: {
                url: TEST_VIDEO_URL,
                language: 'pt',
            }
        }) as unknown as {
            structuredContent: {
                transcript: Array<{ text: string; start: number; duration: number }>;
                segmentCount: number;
            }
        };

        assert.ok(
            result.structuredContent?.transcript?.length > 0,
            'Should return transcript segments'
        );
        assert.ok(
            result.structuredContent?.segmentCount > 10,
            'Should have more than 10 segments'
        );
        assert.ok(
            typeof result.structuredContent?.transcript[0].start === 'number',
            'Start should be a number'
        );
        assert.ok(
            typeof result.structuredContent?.transcript[0].text === 'string',
            'Text should be a string'
        );
    });

    it('should get transcript as plain text', async () => {
        const result = await client.callTool({
            name: 'get_transcript_text',
            arguments: {
                url: TEST_VIDEO_URL,
            }
        });

        const content = result.content as Array<{ type: string; text: string }>;
        const textOutput = content.find(c => c.type === 'text')?.text || '';

        assert.ok(textOutput.length > 100, 'Text output should have meaningful content');
        assert.ok(!textOutput.includes('[0.'), 'Plain text should not contain timestamp markers');
    });

    it('should search within transcript', async () => {
        const result = await client.callTool({
            name: 'search_transcript',
            arguments: {
                url: TEST_VIDEO_URL,
                query: 'Graphify',
                language: 'en',
            }
        });

        const content = result.content as Array<{ type: string; text: string }>;
        const textOutput = content.find(c => c.type === 'text')?.text || '';

        assert.ok(
            textOutput.includes('Graphify'),
            'Search should find the query term in the transcript'
        );
        assert.ok(
            textOutput.includes('Match'),
            'Search should return formatted matches'
        );
    });

    it('should extract transcript using youtu.be short URL', async () => {
        const result = await client.callTool({
            name: 'get_transcript',
            arguments: {
                url: 'https://youtu.be/nQdxsjaeLSk',
            }
        });

        const content = result.content as Array<{ type: string; text: string }>;
        const textOutput = content.find(c => c.type === 'text')?.text || '';
        assert.ok(textOutput.length > 100, 'Should work with youtu.be URLs');
    });

    it('should extract transcript using plain video ID', async () => {
        const result = await client.callTool({
            name: 'get_transcript',
            arguments: {
                url: 'nQdxsjaeLSk',
            }
        });

        const content = result.content as Array<{ type: string; text: string }>;
        const textOutput = content.find(c => c.type === 'text')?.text || '';
        assert.ok(textOutput.length > 100, 'Should work with plain video IDs');
    });

    it('should return error for invalid video', async () => {
        const result = await client.callTool({
            name: 'get_transcript',
            arguments: {
                url: 'https://www.youtube.com/watch?v=INVALID___ID',
            }
        });

        assert.ok(result.isError, 'Should return error for invalid video');
    });
});
