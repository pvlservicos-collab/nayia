# 🚀 Atlas Eye CRM — Quick Start (5 min)

## 1️⃣ Install Dependencies

```bash
cd atlas-eye
npm install
```

## 2️⃣ Configure Environment

Create `.env.local` file:

```bash
cp .env.local.example .env.local
```

Then edit `.env.local` with your Supabase credentials:

```env
NEXT_PUBLIC_SUPABASE_URL=https://hklfcfadultzuhwgkqmz.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here
```

**To get these credentials:**
- Go to https://app.supabase.com
- Select your project
- Settings → API
- Copy the URL and Anon Key

## 3️⃣ Start Development Server

```bash
npm run dev
```

Open http://localhost:3000 in your browser

## 4️⃣ Explore the Application

### Pipeline Board
Navigate to http://localhost:3000/pipeline

**What you'll see:**
- Kanban board with stages (Novo, Qualificado, Proposta, Fechado)
- Lead cards with interest levels and tags
- Yellow "+ Novo Lead" button

**What you can do:**
- View all leads grouped by stage
- See lead owner avatars
- Check last activity timestamps
- (Coming: drag-drop between stages)

### Chat Interface
Navigate to http://localhost:3000/chat

**What you'll see:**
- Left panel: List of leads (like WhatsApp)
- Right panel: Activity timeline
- Activity composer with type selector (Message, Note, Call, Email)

**What you can do:**
- Select a lead to view conversation
- Add notes and activities
- See real-time message delivery
- (Coming: full multi-channel support)

## 📁 Project Structure

```
atlas-eye/
├── src/
│   ├── app/                 # Pages
│   │   ├── page.tsx         # Home (links to pipeline/chat)
│   │   ├── pipeline/        # /pipeline page
│   │   └── chat/            # /chat page
│   │
│   ├── components/
│   │   ├── Pipeline/        # Kanban components
│   │   └── Chat/            # Chat components
│   │
│   ├── hooks/               # Custom React hooks
│   │   ├── usePipeline.ts   # Fetch pipelines & stages
│   │   ├── useLeads.ts      # Fetch leads + realtime
│   │   ├── useTimeline.ts   # Fetch activities
│   │   └── useAuth.ts       # Auth state
│   │
│   └── lib/
│       ├── supabase.ts      # Supabase client
│       ├── types.ts         # TypeScript types
│       └── utils.ts         # Helpers (date, colors, etc)
│
├── .env.local               # ⚠️ NEVER commit this!
├── .env.local.example       # Template
├── package.json
├── tsconfig.json
├── next.config.ts
└── tailwind.config.ts
```

## 🔧 Configuration Files Explained

### `.env.local` (Keep Secret!)
- `NEXT_PUBLIC_SUPABASE_URL`: Your Supabase project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: Public API key (safe to expose in frontend)

### `tsconfig.json`
- Enables TypeScript with strict mode
- Alias `@/*` for importing from `src/`

### `next.config.ts`
- Next.js 15 configuration
- React 19 strict mode enabled

### `tailwind.config.ts`
- Tailwind CSS with custom colors
- Yellow accent color: `#f9f506`
- Uses Spline Sans font

## 📚 Component Hierarchy

```
Home Page
├── [Click Pipeline]
│   └── PipelineBoard
│       └── StageColumn[]
│           └── LeadCard[]
│
└── [Click Chat]
    ├── LeadList
    │   └── [Select Lead]
    └── ChatWindow
        ├── ActivityTimeline
        └── ActivityComposer
```

## 🪝 Custom Hooks (Core Logic)

### `usePipeline(organizationId)`
Fetches and manages pipelines and stages

```typescript
const { pipelines, stages, selectedPipelineId, selectPipeline } =
  usePipeline(orgId)
```

### `useLeads(organizationId, stageId?)`
Fetches leads with real-time subscription + move functionality

```typescript
const { leads, moveLeadToStage, updateLead } = useLeads(orgId, stageId)
```

### `useTimeline(leadId)`
Fetches activities with real-time subscription + add activity

```typescript
const { activities, addActivity } = useTimeline(leadId)
```

### `useAuth()`
Gets current user and organization context

```typescript
const { user, organizationId, currentOrganization } = useAuth()
```

## 🔄 Data Flow

### Viewing Leads
```
User opens /pipeline
  → useAuth() gets organizationId
  → usePipeline() fetches pipelines
  → useLeads() fetches leads + subscribes to changes
  → StageColumn renders lead cards
```

### Moving a Lead
```
User drags lead to new stage
  → moveLeadToStage() called
  → UPDATE leads table
  → Realtime triggers for all users
  → All UIs update automatically
```

### Adding Activity
```
User types message + clicks send
  → addActivity() called
  → INSERT into lead_activities
  → Realtime triggers
  → Timeline updates automatically
```

## 🧪 Quick Tests

### Test 1: Data Loading
1. Go to `/pipeline`
2. Check browser console (F12)
3. Should see leads loaded: `{leads: [...]}`
4. No red errors

### Test 2: Real-time
1. Open `/chat` in two browser tabs
2. Send message in one tab
3. Should appear in other tab within 1 second
4. Check WebSocket connection: DevTools → Network → WS

### Test 3: Supabase Connection
1. Open http://localhost:3000
2. Check browser console
3. Verify no auth/CORS errors
4. Should see user logged in (or auth page)

## 🚨 Common Issues

### "Missing environment variables"
- Check `.env.local` exists
- Verify `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are set
- Restart dev server after changes

### "Cannot read property 'data' of undefined"
- Check Supabase table exists: https://app.supabase.com
- Verify RLS policies: Settings → Policies
- Check table name spelling in hook

### "Real-time not updating"
- Verify Realtime is enabled: Supabase → Database → Replication
- Check filter syntax in hook
- Reload page to re-subscribe

### Port 3000 already in use
```bash
npm run dev -- -p 3001
# Opens on port 3001 instead
```

## 📦 Dependencies

| Package | Purpose |
|---------|---------|
| `next` v15 | React framework |
| `react` v19 | UI library |
| `@supabase/supabase-js` | Database client |
| `tailwindcss` | CSS framework |
| `typescript` | Type safety |

## 🎯 Next Steps

### After confirming it works:
1. **Add Authentication** (enable Supabase Auth)
2. **Enable Drag-Drop** (install react-beautiful-dnd)
3. **Deploy to Vercel** (git push → vercel auto-deploys)
4. **User Testing** (gather feedback)
5. **Production Launch** (monitor and optimize)

## 📖 Full Documentation

For detailed setup, architecture, and troubleshooting:

1. **SETUP.md** - Complete installation guide
2. **IMPLEMENTATION_GUIDE.md** - Component & hook documentation
3. **ARQUITECTURA_TECNICA.md** - Technical architecture
4. **README.md** - Project overview

## 🆘 Stuck?

1. Check `.env.local` has credentials
2. Check browser console (F12 → Console tab)
3. Check Supabase logs: https://app.supabase.com/project/[id]/logs
4. Read SETUP.md troubleshooting section

---

**Version:** 1.0.0
**Created:** 2026-02-18
**Status:** ✅ Ready to run
