# compound-ralph Webhook Server

Webhook server for compound-ralph to receive and process GitHub events.

## Overview

This server provides a webhook endpoint that listens for GitHub events (issue comments, PRs, pushes, CI checks) and can trigger automated actions for the compound-ralph system.

## Quick Start

```bash
cd webhook
npm install
npm start
```

The server will start on port 3457 (or PORT env var).

## Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `PORT` | Server port | 3457 |
| `WEBHOOK_SECRET` | GitHub webhook secret for signature verification | (empty) |

## Endpoints

### `GET /health`
Health check endpoint. Returns:
```json
{
  "status": "ok",
  "service": "compound-ralph-webhook"
}
```

### `POST /webhook`
GitHub webhook endpoint. Handles:
- `issue_comment` - Comments on issues/PRs
- `issues` - Issue lifecycle events
- `pull_request` - PR events
- `push` - Push events
- `check_run` / `check_suite` - CI check events

## GitHub Setup

### 1. Set webhook secret (optional but recommended)

Generate a secret:
```bash
openssl rand -hex 32
```

Set as environment variable:
```bash
export WEBHOOK_SECRET="your-generated-secret"
```

### 2. Configure webhook in GitHub

1. Go to repository Settings → Webhooks → Add webhook
2. **Payload URL**: `https://your-domain.com/webhook` (or localhost for testing)
3. **Content type**: `application/json`
4. **Secret**: The same secret you set in WEBHOOK_SECRET
5. **Events**: Select individual events:
   - Issue comments
   - Issues
   - Pull requests
   - Push
   - Workflow runs (for CI checks)

### 3. For local development with ngrok

```bash
npm install -g ngrok
ngrok http 3457
```

Use the ngrok URL as your webhook payload URL.

## Integration with compound-ralph

The webhook can trigger compound-ralph actions. Example logic:

```javascript
// In server.js - process webhook events
if (event === 'issue_comment' && action === 'created') {
  // Check for command patterns like "/cr implement"
  if (comment.body.startsWith('/cr ')) {
    const command = comment.body.slice(4).trim();
    // Spawn compound-ralph to handle the command
    spawnCompoundRalph(command);
  }
}
```

## File Structure

```
compound-ralph/
├── webhook/
│   ├── server.js      # Main webhook server
│   ├── package.json   # Dependencies
│   └── README.md      # This file
├── cr                 # compound-ralph CLI
├── templates/         # Planning templates
├── plans/             # Saved plans
└── specs/             # Implementation specs
```

## Development

```bash
# Run with auto-reload
npm run dev

# Test health endpoint
curl http://localhost:3457/health

# Test webhook endpoint (with signature)
SIGNATURE="sha256=$(echo -n '{\"test\":1}' | openssl dgst -sha256 -hmac "secret" | cut -d' ' -f2)"
curl -X POST http://localhost:3457/webhook \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: $SIGNATURE" \
  -H "X-GitHub-Event: push" \
  -d '{"test":1}'
```

## License

MIT - Same as compound-ralph
