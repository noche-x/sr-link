-- Link codes, links and Discord OAuth tokens, stored in SQLite.
--
-- Times are REAL seconds since the epoch. IDs and phone numbers are TEXT, because SQLite INTEGER columns come back
-- as int64 cdata from the binding.
local openssl = require("openssl")
local sqlite3 = require("sqlite3")
local config = require("./config")

local CODE_LIFETIME = 5 * 60

local db = {}

local conn = sqlite3.open(config.database)
conn:exec([[
	PRAGMA journal_mode = WAL;

	CREATE TABLE IF NOT EXISTS codes (
		code TEXT PRIMARY KEY,
		discord_id TEXT NOT NULL UNIQUE,
		discord_name TEXT NOT NULL,
		expires_at REAL NOT NULL
	);

	CREATE TABLE IF NOT EXISTS links (
		discord_id TEXT PRIMARY KEY,
		discord_name TEXT NOT NULL,
		steam_id TEXT NOT NULL UNIQUE,
		phone_number TEXT NOT NULL,
		game_name TEXT NOT NULL,
		linked_at REAL NOT NULL
	);

	CREATE TABLE IF NOT EXISTS tokens (
		discord_id TEXT PRIMARY KEY,
		access_token TEXT NOT NULL,
		refresh_token TEXT NOT NULL,
		expires_at REAL NOT NULL
	);
]])

---@param query string SQL with ? placeholders
---@vararg any placeholder values
---@return table|nil row column values in select order
local function row(query, ...)
	local statement = conn:prepare(query)
	local result = statement:bind(...):step()
	statement:close()
	return result
end

---@return string code
local function random_code()
	-- values at or above the largest multiple of a million would make low codes more likely, so they are redrawn
	local limit = math.floor(2 ^ 32 / 1e6) * 1e6
	while true do
		local b1, b2, b3, b4 = openssl.random(4):byte(1, 4)
		local value = b1 + b2 * 256 + b3 * 256 ^ 2 + b4 * 256 ^ 3
		if value < limit then
			return ("%06d"):format(value % 1e6)
		end
	end
end

-- the part of create_code inside its transaction
---@param discord_id string
---@param discord_name string
---@return string code
---@return number expires_at
local function insert_code(discord_id, discord_name)
	local now = os.time()
	row("DELETE FROM codes WHERE discord_id = ? OR expires_at < ?", discord_id, now)
	local code = random_code()
	while row("SELECT 1 FROM codes WHERE code = ?", code) do
		code = random_code()
	end
	local expires_at = now + CODE_LIFETIME
	row("INSERT INTO codes VALUES (?, ?, ?, ?)", code, discord_id, discord_name, expires_at)
	return code, expires_at
end

-- the part of redeem_code inside its transaction
---@param code string
---@param player table
---@return table|nil link
---@return string|nil replaced_discord_id
local function redeem(code, player)
	local found = row("SELECT discord_id, discord_name FROM codes WHERE code = ? AND expires_at >= ?", code, os.time())
	if not found then
		return nil
	end
	local discord_id, discord_name = found[1], found[2]
	local previous = db.find_link("steam_id", player.steam_id)
	local replaced_id
	if previous and previous.discord_id ~= discord_id then
		replaced_id = previous.discord_id
	end

	row("DELETE FROM codes WHERE code = ?", code)
	row("DELETE FROM links WHERE discord_id = ? OR steam_id = ?", discord_id, player.steam_id)
	row("INSERT INTO links VALUES (?, ?, ?, ?, ?, ?)", discord_id, discord_name, player.steam_id,
		tostring(player.phone_number), player.player_name, os.time())
	return db.find_link("discord_id", discord_id), replaced_id
end

---@param discord_id string
---@param discord_name string
---@return string code
---@return number expires_at seconds since the epoch
function db.create_code(discord_id, discord_name)
	conn:exec("BEGIN IMMEDIATE")
	local ok, code, expires_at = pcall(insert_code, discord_id, discord_name)
	if not ok then
		conn:exec("ROLLBACK")
		error(code, 0)
	end
	conn:exec("COMMIT")
	return code, expires_at
end

---@param code string 6 digit code
---@param player table { steam_id, phone_number, player_name } from the master server's auth packet
---@return table|nil link the new link, nil when the code is unknown or expired
---@return string|nil replaced_discord_id the Discord user who had this Sub Rosa account before, if someone else
function db.redeem_code(code, player)
	conn:exec("BEGIN IMMEDIATE")
	local ok, link, replaced = pcall(redeem, code, player)
	if not ok then
		conn:exec("ROLLBACK")
		error(link, 0)
	end
	conn:exec("COMMIT")
	return link, replaced
end

---@param column string "discord_id" or "steam_id"
---@param value string
---@return table|nil link { discord_id, discord_name, steam_id, phone_number, game_name, linked_at }
function db.find_link(column, value)
	assert(column == "discord_id" or column == "steam_id", "cannot find links by " .. tostring(column))
	local found = row(("SELECT * FROM links WHERE %s = ?"):format(column), value)
	if not found then
		return nil
	end
	return {
		discord_id = found[1],
		discord_name = found[2],
		steam_id = found[3],
		phone_number = found[4],
		game_name = found[5],
		linked_at = found[6],
	}
end

---@param discord_id string
---@return boolean removed false when nothing was linked
function db.unlink(discord_id)
	local removed = db.find_link("discord_id", discord_id) ~= nil
	row("DELETE FROM links WHERE discord_id = ?", discord_id)
	return removed
end

---@param discord_id string
---@param access_token string
---@param refresh_token string
---@param expires_at number seconds since the epoch
function db.save_tokens(discord_id, access_token, refresh_token, expires_at)
	row("INSERT OR REPLACE INTO tokens VALUES (?, ?, ?, ?)", discord_id, access_token, refresh_token, expires_at)
end

---@param discord_id string
---@return table|nil tokens { access_token, refresh_token, expires_at }, nil when they never opened Linked Roles
function db.find_tokens(discord_id)
	local found = row("SELECT access_token, refresh_token, expires_at FROM tokens WHERE discord_id = ?", discord_id)
	if not found then
		return nil
	end
	return { access_token = found[1], refresh_token = found[2], expires_at = found[3] }
end

---@param discord_id string
function db.delete_tokens(discord_id)
	row("DELETE FROM tokens WHERE discord_id = ?", discord_id)
end

return db
