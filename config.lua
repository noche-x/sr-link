-- Settings, read from environment variables. See .env.example.
local config = {}

--- Reads an environment variable. Errors when it is unset and there is no default.
---@param name string variable name
---@param default any|nil value used when the variable is unset or empty
---@return any value
local function read_env(name, default)
	local value = process.env[name]
	if value == nil or value == "" then
		value = default
	end
	if value == nil then
		error("missing required environment variable " .. name, 0)
	end
	return value
end

config.udp_port = tonumber(read_env("UDP_PORT", "27584"))
config.server_name = read_env("SERVER_NAME", "Discord Link"):sub(1, 31)

config.http_port = tonumber(read_env("HTTP_PORT", "8788"))
config.public_url = read_env("PUBLIC_URL"):gsub("/$", "")
-- Discord only talks to HTTPS
if not config.public_url:match("^https://") then
	error("PUBLIC_URL must start with https://", 0)
end
config.database = read_env("DATABASE", "links.db")

config.discord_application_id = read_env("DISCORD_APPLICATION_ID")
config.discord_public_key = read_env("DISCORD_PUBLIC_KEY")
config.discord_client_secret = read_env("DISCORD_CLIENT_SECRET")
-- only `luvit main.lua register` needs it
config.discord_bot_token = process.env.DISCORD_BOT_TOKEN


return config
