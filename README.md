<img src="discord/icon.png" alt="" width="96" height="96">

# SR Link

Officially hosted at https://srdiscord.link

Links a player's Discord account to their Sub Rosa account.

- **Pseudo Sub Rosa Server** (`subrosa/`): A passworded server that a player needs to enter a 6 digit code given from the Discord app, and the connect screen shows the result.
- **Discord app** (`discord/`): The panel with generate code and status buttons, and Linked Roles, so any Discord server can give a role to linked players. Links are permanent.

## Setup

### Requirements

- [Luvit](https://luvit.io)
- SQLite's library: Debian/Ubuntu run `apt install libsqlite3-dev`, since the binding loads `libsqlite3.so`.
- Dependencies: `lit install` in the root of this folder.

### Configuring

Copy `.env.example` to `.env` and fill it appropiately. `PUBLIC_URL` is the HTTPS address Discord will reach.

`TOKEN_ENCRYPTION_KEY` encrypts the stored names, phone numbers and Discord tokens with AES-256-GCM, `discord_id` and `steam_id` stay plain because links are looked up by them. Make one with `openssl rand -hex 32` and keep a copy in a password manager, away from the database and its backups: values saved under a lost key cannot be read. Put values that contain spaces in quotes, `SERVER_NAME="Sub Rosa Link"`, or sourcing `.env` in a shell breaks.

Make sure to run a HTTPS reverse proxy on the `HTTP_PORT` set in `.env`
And also allow your firewall for the pseudo Sub Rosa server's port set in `.env`

### Running

```sh
luvit main.lua register
```

Run this once to register commands with Discord.

```sh
luvit main.lua
```

Should print `public address is …` once the master server answers the heartbeat.

### Discord

Create an app in the [Discord Developer Portal](https://discord.com/developers/applications) and put its application id, public key, client secret and bot token in `.env`.

Then in the app's settings:

- **General Information**: set Interactions Endpoint URL to `PUBLIC_URL/interactions` and Linked Roles Verification URL to `PUBLIC_URL/linked-role`.
- **OAuth2**: add `PUBLIC_URL/oauth/callback` as a redirect.
- **Installation**: enable User Install and Guild Install. Guild Install is there so servers can add the app for Linked Roles. Send people to the app's own install link, `https://discord.com/oauth2/authorize?client_id=<application id>`, which is what the website uses. A link with its own `redirect_uri` and `response_type=code` left installs unfinished for some users.
- **Activities**: keep them off.

Discord pings the interactions endpoint when you save it, so the app has to be running first.
