# Life Organizer

A Phoenix LiveView application that helps organize life with journal entries, AI-powered chat assistance, and smart todo management. Built with clean, modern design principles and a focus on user experience.

## Features

- **Journal Management**: Write and organize journal entries with markdown support, mood tracking, and date organization
- **AI Chat Assistant**: Context-aware AI conversations that can create and manage todos based on your journal entries
- **Smart Todo Management**: Priority-based todos with AI extraction, comments, interactive checkboxes, and due date tracking
- **MCP Server Integration**: Model Context Protocol server for external AI tool access
- **Modern UI/UX**: Clean three-column responsive layout with real-time updates

## Technology Stack

- **Backend**: Elixir/Phoenix LiveView with MySQL database
- **Frontend**: Phoenix LiveView with Tailwind CSS
- **AI Integration**: Anthropic Claude API (claude-sonnet-4-0 model)
- **Database**: MySQL with Ecto ORM
- **Real-time**: Phoenix LiveView for interactive UI

## Prerequisites

Before setting up the project, ensure you have the following installed:

- **Elixir 1.14+** and **Erlang/OTP 25+**
- **Node.js 18+** and **npm** (for asset compilation)
- **MySQL** (recommended via Docker)
- **Git** (for version control)

### Installing Elixir

#### macOS
```bash
# Using Homebrew
brew install elixir

# Or using asdf (recommended for version management)
asdf plugin-add erlang
asdf plugin-add elixir
asdf install erlang latest
asdf install elixir latest
```

#### Linux (Ubuntu/Debian)
```bash
# Add Erlang Solutions repository
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update

# Install Erlang and Elixir
sudo apt-get install esl-erlang elixir
```

### Installing MySQL

#### Using Docker (Recommended)
```bash
# Run MySQL in a container
docker run --name life-org-mysql \
  -e MYSQL_ROOT_PASSWORD=root \
  -p 3306:3306 \
  -d mysql:8.0

# Or use docker-compose
cat > docker-compose.yml << EOF
version: '3.8'
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: life_org_dev
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  mysql_data:
EOF

docker-compose up -d
```

#### Native Installation
- **macOS**: `brew install mysql`
- **Linux**: `sudo apt-get install mysql-server`

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/life-org.git
cd life-org
```

### 2. Environment Setup
Create a `.env` file in the project root:
```bash
# Required: Set your Anthropic API key
export ANTHROPIC_API_KEY="your-anthropic-api-key-here"

# Optional: Customize database settings if needed
export DATABASE_URL="ecto://root:root@127.0.0.1:3306/life_org_dev"
```

Load the environment variables:
```bash
source .env
```

### 3. Install Dependencies
```bash
# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies for assets
cd assets && npm install && cd ..
```

### 4. Database Setup
```bash
# Create and migrate the database
mix ecto.create
mix ecto.migrate

# Optional: Run seeds if available
mix run priv/repo/seeds.exs
```

### 5. Start the Development Server
```bash
# Start the Phoenix server
mix phx.server
```

The application will be available at:
- **HTTP**: http://localhost:4000
- **HTTPS**: https://localhost:4001 (with self-signed certificate)
- **MCP Server**: http://localhost:4000/mcp

## Development Workflow

### Using the Built-in Setup Command
For a complete setup in one command:
```bash
mix setup
```
This runs: `deps.get`, `ecto.setup`, `assets.setup`, and `assets.build`

### Common Development Commands
```bash
# Reset database (drop and recreate)
mix ecto.reset

# Run tests
mix test

# Build assets for development
mix assets.build

# Build assets for production
mix assets.deploy

# Generate SSL certificates for HTTPS development
mix phx.gen.cert
```

### Database Operations
```bash
# Create a new migration
mix ecto.gen.migration migration_name

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Check migration status
mix ecto.migrations
```

## Configuration

### Database Configuration
The default development configuration connects to MySQL at:
- **Host**: 127.0.0.1
- **Port**: 3306
- **Username**: root
- **Password**: root
- **Database**: life_org_dev

To customize, edit `config/dev.exs` or set the `DATABASE_URL` environment variable.

### API Configuration
Set your Anthropic API key as an environment variable:
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

The application uses the Claude Sonnet 4 model for AI interactions.

### SSL Configuration (Optional)
For HTTPS development, generate SSL certificates:
```bash
mix phx.gen.cert
```

## Project Structure

```
life-org/
├── assets/                 # Frontend assets (JS, CSS)
├── config/                 # Application configuration
├── lib/
│   ├── life_org/          # Core application logic
│   │   ├── accounts/      # User management
│   │   ├── conversations/ # Chat functionality
│   │   ├── journal/       # Journal entries
│   │   ├── todos/         # Todo management
│   │   └── repo.ex        # Database interface
│   └── life_org_web/      # Web interface
│       ├── components/    # LiveView components
│       ├── controllers/   # Phoenix controllers
│       └── live/          # LiveView modules
├── priv/
│   ├── repo/migrations/   # Database migrations
│   └── static/           # Static assets
└── test/                 # Test files
```

## MCP Server Integration

The application includes a Model Context Protocol server that allows external AI tools to interact with your data.

### Connecting Claude Desktop
Add to your Claude Desktop MCP configuration:
```json
{
  "mcpServers": {
    "life-org": {
      "command": "curl",
      "args": ["-N", "-H", "Content-Type: application/json", "http://localhost:4000/mcp"],
      "env": {}
    }
  }
}
```

### Available MCP Tools
- **Search Todos**: Find todos by query, tags, or completion status
- **Search Journal**: Search journal entries with mood indicators

## Troubleshooting

### Common Issues

#### MySQL Connection Issues
```bash
# Error: Failed to connect to MySQL
# Solution: Ensure MySQL is running
docker start life-org-mysql

# Error: Access denied for user 'root'
# Solution: Check MySQL credentials in config/dev.exs
```

#### Asset Compilation Issues
```bash
# Error: esbuild or tailwind not found
# Solution: Reinstall assets
mix assets.setup

# Error: Node modules missing
# Solution: Reinstall npm dependencies
cd assets && rm -rf node_modules && npm install
```

#### Elixir/Mix Issues
```bash
# Error: Mix not found
# Solution: Ensure Elixir is properly installed
elixir --version

# Error: Dependencies not compiled
# Solution: Clean and reinstall dependencies
mix deps.clean --all
mix deps.get
mix deps.compile
```

#### Port Already in Use
```bash
# Error: Port 4000 already in use
# Solution: Kill existing process or change port
lsof -ti:4000 | xargs kill -9

# Or change port in config/dev.exs
config :life_org, LifeOrgWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001]
```

#### Database Migration Issues
```bash
# Error: Database doesn't exist
mix ecto.create

# Error: Migration failed
# Solution: Check migration file and database state
mix ecto.migrations
mix ecto.rollback
```

### Development Tips

1. **Hot Reloading**: Phoenix automatically reloads code changes. If it stops working, restart with `mix phx.server`

2. **Database Reset**: Use `mix ecto.reset` to completely reset your database during development

3. **Asset Watching**: Assets are watched automatically in development. If changes aren't reflected, check the watchers in `config/dev.exs`

4. **Console Access**: Use `iex -S mix phx.server` to start the server with an interactive Elixir console

5. **Log Levels**: Adjust logging in `config/dev.exs` for debugging

### Getting Help

- **Phoenix Guides**: https://hexdocs.pm/phoenix/overview.html
- **LiveView Documentation**: https://hexdocs.pm/phoenix_live_view/
- **Elixir Documentation**: https://elixir-lang.org/docs.html
- **Ecto Documentation**: https://hexdocs.pm/ecto/

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Ensure tests pass (`mix test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
