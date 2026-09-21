# n8n-nodes-atlaseye

This is an n8n community node that integrates with [Atlas Eye CRM](https://atlaseye.com), allowing you to automate your CRM workflows directly from n8n.

![Atlas Eye](nodes/AtlasEye/atlas-eye.svg)

## Installation

### Community Nodes (Recommended)

1. Go to **Settings → Community Nodes** in your n8n instance
2. Select **Install a community node**
3. Enter `n8n-nodes-atlaseye`
4. Agree to risks and click **Install**

### Manual Installation

```bash
cd ~/.n8n/nodes
npm install n8n-nodes-atlaseye
```

Then restart your n8n instance.

## Configuration

1. Create an **API Token** in Atlas Eye: **Settings → API**
2. In n8n, create new credentials of type **Atlas Eye API**
3. Paste your API token (starts with `atl_`)
4. Set the Base URL of your Atlas Eye instance

## Available Resources & Operations

| Resource | Operations |
|----------|-----------|
| **Lead** | List, Create, Update |
| **Lead Message** | Send Message |
| **Lead History** | Add Event, Edit Event, Delete Event |
| **Pipeline** | List, Get, Create, Update, Delete |
| **Pipeline Stage** | List, Get, Create, Update, Delete, List Colors |
| **User** | List, Invite, Remove |
| **Notification** | Send (single or broadcast) |

## Lead Operations

### List Leads
Retrieve a paginated list of leads with optional filters:
- **Search Query**: Search by name, email, or phone
- **Phone**: Filter by phone number
- **Assigned To**: Filter by member ID
- **Status**: Filter by stage name
- **Tags**: Filter by specific tags
- **Pipeline ID**: Filter by pipeline

### Create Lead
Create a new lead with name, email, phone, pipeline, status, tags, and assignment.

### Update Lead
Update lead fields including name, email, phone, assignment, pipeline, status, tags, and custom fields.

## Lead Message Operations

### Send Message
Send a message to a lead's chat. Supports:
- **Types**: WhatsApp, Note, Email, System
- **Direction**: Inbound or Outbound
- **Media Type**: Image, Video, Audio, Document, Sticker
- **Reply To Message ID**: Reply to a specific quoted message

## Pipeline Operations

Full CRUD operations on pipelines and their stages, including:
- Create pipelines and stages with colors and ordering
- Update names, colors, and positions
- Soft-delete pipelines and stages

## Notification Operations

### Send Notification
Send notifications to:
- A **specific member** by providing their Member ID
- **All members** (broadcast) by leaving the recipient empty

Notification types: `info`, `warning`, `success`, `error`.

## Source Field

All mutating operations require a `source` field. This identifies who triggered the action:

| Value | Description |
|-------|-------------|
| `ai_agent` | Triggered by an AI agent / automation (default) |
| `human` | Triggered by a human action |
| `system` | Triggered by a system process |

## Example Workflow

```
[Webhook] → [Atlas Eye: Create Lead] → [Atlas Eye: Send Message] → [Atlas Eye: Send Notification]
```

1. A webhook receives a new contact from your website
2. Atlas Eye creates a new lead in the correct pipeline
3. A welcome note is sent to the lead's chat
4. A notification alerts your sales team

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Watch mode
npm run dev
```

## License

MIT
