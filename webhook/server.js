const express = require('express');
const crypto = require('crypto');
const http = require('http');

const app = express();
const PORT = process.env.PORT || 3457;
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || '';
const BOARD_URL = process.env.BOARD_URL || 'http://localhost:3456';

// Parse raw body for signature verification
app.use(express.json({
  verify: (req, res, buf) => {
    req.rawBody = buf;
  }
}));

// Logging middleware
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${req.method} ${req.path}`);
  if (req.body && Object.keys(req.body).length > 0) {
    console.log('Payload:', JSON.stringify(req.body, null, 2).slice(0, 500));
  }
  next();
});

// Verify GitHub webhook signature
function verifySignature(payload, signature) {
  if (!WEBHOOK_SECRET) return true; // Skip if no secret configured

  const hmac = crypto.createHmac('sha256', WEBHOOK_SECRET);
  const digest = 'sha256=' + hmac.update(payload).digest('hex');

  return crypto.timingSafeEqual(
    Buffer.from(signature || ''),
    Buffer.from(digest)
  );
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'compound-ralph-webhook' });
});

// Create a task on the KitsuneOps board
async function createBoardTask(title, source, priority, tags, body = '') {
  const taskData = {
    title: title,
    status: 'queued',
    source: source,
    priority: priority || 2,
    tags: tags || [],
  };
  
  if (body) {
    taskData.body = body;
  }

  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(taskData);
    const url = new URL('/api/tasks', BOARD_URL);
    
    const options = {
      hostname: url.hostname,
      port: url.port || 80,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
      },
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          console.log(`[Board] Task created: "${title}"`);
          resolve(JSON.parse(data));
        } else {
          console.error(`[Board] Failed to create task: ${res.statusCode} ${data}`);
          reject(new Error(`Board API error: ${res.statusCode}`));
        }
      });
    });

    req.on('error', (e) => {
      console.error(`[Board] Error creating task: ${e.message}`);
      reject(e);
    });

    req.write(postData);
    req.end();
  });
}

// Webhook endpoint
app.post('/webhook', (req, res) => {
  const signature = req.headers['x-hub-signature-256'];
  const event = req.headers['x-github-event'];
  const deliveryId = req.headers['x-github-delivery'];

  console.log(`[Webhook] Event: ${event}, Delivery: ${deliveryId}`);

  // Verify signature if secret is configured
  if (WEBHOOK_SECRET && !verifySignature(req.rawBody, signature)) {
    console.error('[Webhook] Invalid signature');
    return res.status(401).json({ error: 'Invalid signature' });
  }

  const { action, repository, sender, comment, issue, pull_request } = req.body;

  // Handle different event types
  switch (event) {
    case 'issue_comment':
      if (action === 'created' && comment && issue) {
        console.log(`[Webhook] Issue comment on #${issue.number}: ${comment.body.slice(0, 100)}...`);
        // TODO: Trigger webhook processing logic
        // This could spawn cr implement, send notification, etc.
      }
      break;

    case 'issues':
      if (action === 'opened' && issue) {
        console.log(`[Webhook] New issue #${issue.number}: ${issue.title}`);
        // Create a board task for the new issue
        const taskTitle = `[GitHub #${issue.number}] ${issue.title}`;
        const taskBody = `GitHub Issue: ${repository?.full_name}#${issue.number}\n\n${issue.body || 'No description provided.'}`;
        
        createBoardTask(taskTitle, 'github', 2, ['github', 'issue'], taskBody)
          .catch(err => console.error('[Webhook] Failed to create board task:', err.message));
      } else if (action) {
        console.log(`[Webhook] Issue ${action}: #${issue?.number} - ${issue?.title}`);
      }
      break;

    case 'pull_request':
      if (action === 'opened' && pull_request) {
        console.log(`[Webhook] PR #${pull_request.number}: ${pull_request.title}`);
        // Could update linked board task to in-progress or closed
      } else if (action) {
        console.log(`[Webhook] PR ${action}: #${pull_request?.number} - ${pull_request?.title}`);
      }
      break;

    case 'push':
      console.log(`[Webhook] Push to ${repository?.full_name}: ${req.body.commits?.length || 0} commits`);
      break;

    case 'check_run':
      console.log(`[Webhook] Check run: ${req.body.action}`);
      break;

    case 'check_suite':
      console.log(`[Webhook] CI check: ${req.body.action}`);
      break;

    default:
      console.log(`[Webhook] Unhandled event type: ${event}`);
  }

  // Always respond with 200 to acknowledge receipt
  res.status(200).json({
    received: true,
    event,
    deliveryId,
    action
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`[Webhook Server] Listening on port ${PORT}`);
  console.log(`[Webhook Server] Endpoint: http://localhost:${PORT}/webhook`);
  console.log(`[Webhook Server] Health check: http://localhost:${PORT}/health`);
  if (!WEBHOOK_SECRET) {
    console.log('[Webhook Server] WARNING: WEBHOOK_SECRET not set - signature verification disabled');
  }
});

module.exports = app;
