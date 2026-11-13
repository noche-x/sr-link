local linked_roles = {}

local querystring = require("querystring")

local config = require("../config")
local db = require("../db")
local api = require("./api")


local REDIRECT_URI = config.public_url .. "/oauth/callback"
local REFRESH_BEFORE_S = 60


---@type table<string, boolean> discord_id -> an update is running
linked_roles.updating = {}
---@type table<string, boolean> discord_id -> another update was asked for while one was running
linked_roles.pending = {}

---@param state string random value the callback has to bring back
---@return string url
function linked_roles.sign_in_url(state)
	return "https://discord.com/oauth2/authorize?" .. querystring.stringify({
		client_id = config.discord_application_id,
		redirect_uri = REDIRECT_URI,
		response_type = "code",
		scope = "identify role_connections.write",
		state = state,
		prompt = "consent",
	})
end

---@param discord_id string
---@return table|nil tokens the user's tokens, refreshed if they were about to expire
function linked_roles.fresh_tokens(discord_id)
	local tokens = db.find_tokens(discord_id)
	if not tokens or tokens.expires_at > os.time() + REFRESH_BEFORE_S then
		return tokens
	end

	local refreshed, err = api.request_tokens({
		grant_type = "refresh_token",
		refresh_token = tokens.refresh_token,
	})

	-- a sign in can replace the tokens while we wait
	local current = db.find_tokens(discord_id)
	if current and current.refresh_token == tokens.refresh_token then
		if refreshed then
			db.save_tokens(discord_id, refreshed.access_token, refreshed.refresh_token, os.time() + refreshed.expires_in)
		elseif err == "invalid_grant" then
			db.delete_tokens(discord_id)
		end
	end

	return db.find_tokens(discord_id)
end

---@param discord_id string
function linked_roles.sync(discord_id)
	while linked_roles.pending[discord_id] do
		linked_roles.pending[discord_id] = nil

		local tokens = linked_roles.fresh_tokens(discord_id)
		if tokens then
			local linked = db.find_link("discord_id", discord_id) ~= nil
			api.request(
				"PUT",
				("/users/@me/applications/%s/role-connection"):format(config.discord_application_id),
				"Bearer " .. tokens.access_token,
				{ platform_name = "Sub Rosa", metadata = { linked = linked and 1 or 0 } }
			)
		end
	end
end

-- one update per user at a time, so token refreshes and role writes can't race
---@param discord_id string
function linked_roles.update(discord_id)
	linked_roles.pending[discord_id] = true
	if linked_roles.updating[discord_id] then
		return
	end

	linked_roles.updating[discord_id] = true
	local ok, err = pcall(linked_roles.sync, discord_id)
	linked_roles.updating[discord_id] = nil
	if not ok then
		error(err, 0)
	end
end

---@param discord_id string
function linked_roles.update_logged(discord_id)
	local ok, err = pcall(linked_roles.update, discord_id)
	if not ok then
		print(("Linked Roles update for %s failed: %s"):format(discord_id, tostring(err)))
	end
end

-- nothing waits on this, so errors get printed instead of taking the server down
---@param discord_id string
function linked_roles.update_later(discord_id)
	coroutine.wrap(linked_roles.update_logged)(discord_id)
end

---@param code string oauth code from the callback
---@return table user the Discord user
---@return boolean linked whether they have linked a Sub Rosa account
function linked_roles.finish_sign_in(code)
	local tokens = api.request_tokens({
		grant_type = "authorization_code",
		code = code,
		redirect_uri = REDIRECT_URI,
	})
	if not tokens then
		error("Discord rejected the oauth code")
	end

	local user = api.request("GET", "/users/@me", "Bearer " .. tokens.access_token)
	db.save_tokens(user.id, tokens.access_token, tokens.refresh_token, os.time() + tokens.expires_in)

	linked_roles.update(user.id)

	return user, db.find_link("discord_id", user.id) ~= nil
end

return linked_roles
