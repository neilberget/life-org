# Life Organizer Setup Guide

## Prerequisites

- Elixir 1.14+
- MySQL running (via Docker or locally)
- Node.js for assets compilation

## Installation

1. Install dependencies:
```bash
mix deps.get
cd assets && npm install
cd ..
```

2. Configure your database in `config/dev.exs`:
```elixir
config :life_org, LifeOrg.Repo,
  username: "root",
  password: "root",
  hostname: "127.0.0.1",
  database: "life_org_dev"
```

3. Create and migrate the database:
```bash
mix ecto.create
mix ecto.migrate
```

4. Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

5. Start the server:
```bash
mix phx.server
```

Visit http://localhost:4000 to start organizing your life!