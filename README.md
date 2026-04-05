# Panata — Autonomous Personal Assistant OS

A Telegram-native personal assistant that handles voice/text input, classifies intent, extracts entities, and manages a three-tier task hierarchy (Buckets → Projects → Tasks).

## Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Input | Telegram Bot API | Voice/text messages |
| Orchestration | n8n (self-hosted) | Workflow automation |
| STT | Groq Whisper-large-v3 | Sub-300ms transcription |
| LLM | Groq Llama 3.1 / Gemini 1.5 Flash | Intent classification + entity extraction |
| Database | Supabase (PostgreSQL + pgvector) | State + vector search |
| Tunnel | ngrok | Webhook exposure |

## Quick Start

### 1. Clone & Configure

```bash
git clone https://github.com/2nieGarcia/panata-ai.git
cd panata-ai
cp .env.example .env
# Edit .env with your API keys
```

### 2. Launch Services

```bash
docker compose up -d
```

### 3. Access n8n

- **Local:** http://localhost:5678
- **Webhook URL:** https://YOUR_NGROK_DOMAIN.ngrok-free.app

### 4. Import Workflow

1. Open n8n → Create new workflow
2. Import `n8n-workflow.json`
3. Configure credentials (Telegram, Groq, Supabase)
4. Activate workflow

### 5. Set Up Supabase

Run the SQL files in order:
1. `sql/schema.sql` — Creates tables
2. `sql/seed.sql` — Pre-seeds buckets
3. `sql/functions.sql` — RPC functions

## Environment Variables

| Variable | Description |
|----------|-------------|
| `N8N_USER` | n8n basic auth username |
| `N8N_PASSWORD` | n8n basic auth password |
| `NGROK_AUTHTOKEN` | ngrok auth token |
| `NGROK_DOMAIN` | Your static ngrok domain |
| `TELEGRAM_BOT_TOKEN` | From @BotFather |
| `GROQ_API_KEY` | Groq API key for Whisper + Llama |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_KEY` | Supabase anon/service key |
| `GEMINI_API_KEY` | (Optional) Gemini fallback |

## Project Structure

```
panata-ai/
├── docker-compose.yml      # n8n + ngrok services
├── .env.example            # Environment template
├── n8n-workflow.json       # Main workflow (import to n8n)
├── sql/
│   ├── schema.sql          # Database tables
│   ├── seed.sql            # Pre-seed buckets
│   └── functions.sql       # RPC functions
└── docs/
    └── Panata_Architecture.pdf
```

## Development Phases

- [x] **Phase 1:** Foundation (Telegram → Supabase → Reply) **COMPLETE**
  - Telegram → n8n → Supabase → Telegram works
  - Hard-coded project_id (no LLM yet)
  - Ready for Phase 2
  
  Next: Add router agent + entity extraction

  
- [ ] **Phase 2:** Brain (Router + Entity Extraction)
- [ ] **Phase 3:** HITL Approval (Wait Node + Inline Buttons)
- [ ] **Phase 4:** Voice Input (Groq Whisper)
- [ ] **Phase 5:** RAG Memory (pgvector embeddings)
- [ ] **Phase 6:** Daily Briefing (Cron + LLM synthesis)
- [ ] **Phase 7:** Edge Cases + Polish
- [ ] **Phase 8:** Notion Sync (Optional)

## Architecture Highlights

- **Router Pattern:** Classify intent before extraction (saves tokens)
- **HITL Safety:** New buckets/projects require human approval
- **pgvector in Postgres:** No external vector DB needed at this scale
- **Dual Embedding:** Tasks (what exists) vs Logs (what was done)

## Useful Commands

```bash
# Start services
docker compose up -d

# View logs
docker compose logs -f n8n
docker compose logs -f ngrok

# Restart after .env changes
docker compose down && docker compose up -d

# Check ngrok tunnel
open http://localhost:4040

# Set Telegram webhook manually
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d '{"url": "https://YOUR_DOMAIN.ngrok-free.app/webhook/telegram"}'
```

## License

MIT
