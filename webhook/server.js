const express = require('express');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3457;
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || '';

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
      if (action) {
        console.log(`[Webhook] Issue ${action}: #${issue?.number} - ${issue?.title}`);
      }
      break;

    case 'pull_request':
      if (action) {
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
