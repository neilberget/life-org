Deploy the Life Organizer application to production using the automated deployment script.

Run the following command:

```bash
mix deploy
```

This will:
1. Sync all code to the kestrel server (excluding .git, _build, deps, node_modules)
2. Build the Docker image on the remote server
3. Stop the old container
4. Start the new container
5. Run database migrations automatically

The app will be deployed to: https://lifeorg.kestrel.home

Before deploying, make sure:
- All changes are committed locally (for reference)
- The kestrel server has the required environment variables set in .env
- You have SSH access to neil@kestrel

After deployment completes, verify the app is running at the health check endpoint:
- Check: https://lifeorg.kestrel.home/health
