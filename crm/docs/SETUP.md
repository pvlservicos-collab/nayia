# Atlas Eye CRM - Setup Guide

## 📋 Prerequisites

- Node.js 18+ installed
- npm or yarn package manager
- Supabase project credentials

## 🚀 Installation

### 1. Install Dependencies

```bash
npm install
```

This installs:
- `next`: React framework v15
- `react` & `react-dom`: v19
- `@supabase/supabase-js`: Supabase client
- `tailwindcss`: CSS framework
- `typescript`: Type safety

### 2. Configure Environment Variables

Copy `.env.local.example` to `.env.local`:

```bash
cp .env.local.example .env.local
```

Edit `.env.local` with your Supabase credentials:

```env
NEXT_PUBLIC_SUPABASE_URL=https://hklfcfadultzuhwgkqmz.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here
```

**Where to find these:**
1. Go to https://app.supabase.com
2. Select your project
3. Go to Settings → API
4. Copy the URL and Anon Key

### 3. Start Development Server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## 📁 Project Structure

```
atlas-eye/
├── src/
│   ├── app/              # Next.js App Router pages
│   │   ├── layout.tsx    # Root layout
│   │   ├── page.tsx      # Home page
│   │   ├── pipeline/     # Pipeline Kanban
│   │   └── chat/         # Chat & Timeline
│   │
│   ├── components/       # React components
│   │   ├── Pipeline/     # Kanban board components
│   │   │   ├── PipelineBoard.tsx
│   │   │   ├── StageColumn.tsx
│   │   │   ├── LeadCard.tsx
│   │   │   └── PipelineSelector.tsx
│   │   │
│   │   └── Chat/         # Chat components
│   │       ├── ChatWindow.tsx
│   │       ├── LeadList.tsx
│   │       ├── ActivityTimeline.tsx
│   │       └── ActivityComposer.tsx
│   │
│   ├── hooks/            # Custom React hooks
│   │   ├── usePipeline.ts    # Fetch pipelines & stages
│   │   ├── useLeads.ts       # Fetch leads + realtime
│   │   ├── useTimeline.ts    # Fetch activities
│   │   └── useAuth.ts        # Authentication
│   │
│   ├── lib/              # Utilities & configuration
│   │   ├── supabase.ts   # Supabase client
│   │   ├── types.ts      # TypeScript types
│   │   └── utils.ts      # Helper functions
│   │
│   └── globals.css       # Tailwind CSS
│
├── public/               # Static assets
├── .env.local            # Environment variables (local)
├── .env.local.example    # Example environment
├── package.json          # Dependencies
├── tsconfig.json         # TypeScript config
├── next.config.ts        # Next.js config
└── tailwind.config.ts    # Tailwind config
```

## 🎯 Key Features

### Pipeline Board (`/pipeline`)
- Kanban board with horizontal scrolling stages
- Drag-drop leads between stages
- Lead cards with:
  - AI interest level (color-coded stars)
  - Tags (colored badges)
  - Owner avatar
  - Last activity timestamp

### Chat Interface (`/chat`)
- Left sidebar: List of leads (like WhatsApp)
- Right panel: Activity timeline + composer
- Multi-channel support:
  - 💬 Messages (WhatsApp)
  - 📝 Notes (yellow cards)
  - 📞 Calls (gray pills)
  - 📧 Email (blue cards)

### Real-time Features
- Live updates when leads move between stages
- Real-time message delivery
- Automatic UI refresh on activity changes

## 🔌 Supabase Integration

### Tables Used

- `pipelines`: Sales funnels
- `pipeline_stages`: Stages within each pipeline
- `leads`: Prospect records
- `lead_activities`: Messages, notes, calls, emails
- `lead_tags`: Tags assigned to leads
- `organization_members`: Team members
- `lead_ai_insights`: AI-generated insights

### Real-time Subscriptions

Enabled for:
- `leads` table (INSERT, UPDATE, DELETE)
- `lead_activities` table (INSERT)

### RLS (Row Level Security)

All tables are protected with RLS policies that ensure:
- Users can only see data from their organization
- Only organization members can access data
- No cross-organization data leaks

## 🧪 Development Commands

```bash
# Start dev server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Type checking
npm run type-check
```

## 🌐 Deployment

### Vercel (Recommended)

```bash
# 1. Push to GitHub
git add .
git commit -m "Initial Atlas Eye implementation"
git push origin main

# 2. Go to vercel.com
# 3. Import repository
# 4. Add environment variables:
#    - NEXT_PUBLIC_SUPABASE_URL
#    - NEXT_PUBLIC_SUPABASE_ANON_KEY

# 5. Deploy!
```

## 🐛 Troubleshooting

### "Connection refused" error
- Check that `.env.local` has correct Supabase credentials
- Verify internet connection

### "RLS policy rejected" error
- Ensure `organization_id` filter is included in queries
- Check user has correct role in Supabase

### Realtime not updating
- Verify Realtime is enabled in Supabase settings
- Check browser console for WebSocket errors
- Reload page to re-subscribe

## 📚 Documentation

For more details, see:
- [IMPLEMENTATION_GUIDE.md](../IMPLEMENTATION_GUIDE.md) - Complete integration guide
- [ARQUITECTURA_TECNICA.md](../ARQUITECTURA_TECNICA.md) - Technical architecture
- [README.md](../README.md) - Project overview

## 🤝 Support

For questions or issues:
1. Check [IMPLEMENTATION_GUIDE.md](../IMPLEMENTATION_GUIDE.md) troubleshooting section
2. Review Supabase logs: https://app.supabase.com/project/[project-id]/logs
3. Check browser DevTools console for errors

## ✅ Next Steps

1. ✅ Install dependencies (`npm install`)
2. ✅ Configure environment variables (`.env.local`)
3. ⬜ Start dev server (`npm run dev`)
4. ⬜ Test Pipeline page (`http://localhost:3000/pipeline`)
5. ⬜ Test Chat page (`http://localhost:3000/chat`)
6. ⬜ Deploy to Vercel

---

**Created:** 2026-02-18
**Version:** 1.0.0
**Status:** Ready for Development
