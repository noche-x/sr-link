local interactions = {}

local ffi = require("ffi")

local config = require("../config")
local db = require("../db")


-- from Discord's interaction docs
local INTERACTION_PING = 1
local INTERACTION_COMMAND = 2
local INTERACTION_BUTTON = 3
local RESPONSE_PONG = 1
local RESPONSE_MESSAGE = 4
local RESPONSE_UPDATE_MESSAGE = 7
local FLAG_EPHEMERAL = 64
local COMPONENT_ROW = 1
local COMPONENT_BUTTON = 2
local STYLE_BLUE = 1
local STYLE_GREY = 2

local EVP_PKEY_ED25519 = 1087


-- luvit exports its openssl, lua-openssl can't verify ed25519 since it always hashes with a digest first
ffi.cdef([[
	typedef struct evp_pkey_st EVP_PKEY;
	typedef struct evp_md_ctx_st EVP_MD_CTX;
	EVP_PKEY *EVP_PKEY_new_raw_public_key(int type, void *engine, const unsigned char *key, size_t key_length);
	void EVP_PKEY_free(EVP_PKEY *key);
	EVP_MD_CTX *EVP_MD_CTX_new(void);
	void EVP_MD_CTX_free(EVP_MD_CTX *context);
	int EVP_DigestVerifyInit(EVP_MD_CTX *context, void **key_context, const void *digest, void *engine, EVP_PKEY *key);
	int EVP_DigestVerify(
		EVP_MD_CTX *context,
		const unsigned char *signature,
		size_t signature_length,
		const unsigned char *data,
		size_t data_length
	);
]])

---@param pair string two hex digits
---@return string byte
function interactions.hex_byte(pair)
	return string.char(tonumber(pair, 16))
end

---@param hex string
---@return string bytes
function interactions.from_hex(hex)
	return (hex:gsub("%x%x", interactions.hex_byte))
end

if not config.discord_public_key:match("^" .. ("%x"):rep(64) .. "$") then
	error("DISCORD_PUBLIC_KEY must be 64 hex characters")
end

---@type ffi.cdata* EVP_PKEY for DISCORD_PUBLIC_KEY
interactions.discord_key = ffi.C.EVP_PKEY_new_raw_public_key(
	EVP_PKEY_ED25519,
	nil,
	interactions.from_hex(config.discord_public_key),
	32
)
if interactions.discord_key == nil then
	error("DISCORD_PUBLIC_KEY is not a valid Ed25519 key")
end
interactions.discord_key = ffi.gc(interactions.discord_key, ffi.C.EVP_PKEY_free)

---@param signature string|nil X-Signature-Ed25519 header, hex
---@param timestamp string|nil X-Signature-Timestamp header
---@param body string raw request body
---@return boolean
function interactions.is_signed(signature, timestamp, body)
	if not signature or not timestamp or not signature:match("^" .. ("%x"):rep(128) .. "$") then
		return false
	end

	local context = ffi.C.EVP_MD_CTX_new()
	if context == nil then
		error("could not allocate an EVP_MD_CTX")
	end

	-- ed25519 hashes the message itself, so the digest is nil
	local signed = timestamp .. body
	local valid = ffi.C.EVP_DigestVerifyInit(context, nil, nil, nil, interactions.discord_key) == 1
		and ffi.C.EVP_DigestVerify(context, interactions.from_hex(signature), 64, signed, #signed) == 1

	ffi.C.EVP_MD_CTX_free(context)

	return valid
end

---@param id string custom_id Discord sends back on click
---@param label string
---@param style number STYLE_*
---@return table button
function interactions.button(id, label, style)
	return { type = COMPONENT_BUTTON, custom_id = id, label = label, style = style }
end

---@param text string
---@param buttons table list of interactions.button, empty removes them
---@return table message
function interactions.panel(text, buttons)
	-- discord rejects empty rows
	local components = {}
	if #buttons > 0 then
		components[1] = { type = COMPONENT_ROW, components = buttons }
	end

	return { content = text, flags = FLAG_EPHEMERAL, components = components }
end

---@param user table Discord user
---@return table message
function interactions.status_panel(user)
	local link = db.find_link("discord_id", user.id)
	if not link then
		return interactions.panel("Your Discord is not linked to a Sub Rosa account yet.", {
			interactions.button("generate", "Generate link code", STYLE_BLUE),
		})
	end

	return interactions.panel(
		("**Linked** to Sub Rosa account **%s** (phone %s)."):format(link.game_name, link.phone_number),
		{}
	)
end

---@param user table Discord user
---@return table message
function interactions.code_panel(user)
	-- the code panel's new code button stays after linking
	if db.find_link("discord_id", user.id) then
		return interactions.status_panel(user)
	end

	local code, expires_at = db.create_code(user.id, user.global_name or user.username)
	local text = table.concat({
		("Your link code: **`%s`** (expires <t:%d:R>)"):format(code, expires_at),
		"",
		("1. In Sub Rosa, find **%s** in the server list"):format(config.server_name),
		"2. Enter the code as the server password",
		"3. The connect screen tells you if it worked",
	}, "\n")

	return interactions.panel(text, {
		interactions.button("generate", "New code", STYLE_GREY),
		interactions.button("status", "Check status", STYLE_GREY),
	})
end

interactions.button_panels = {
	generate = interactions.code_panel,
	status = interactions.status_panel,
}

---@param interaction table decoded request body
---@return table response
function interactions.handle(interaction)
	-- discord pings when the endpoint url is saved
	if interaction.type == INTERACTION_PING then
		return { type = RESPONSE_PONG }
	end

	-- member.user in servers, user in dms
	local user = interaction.member and interaction.member.user or interaction.user

	-- app launcher and the user menu command
	if interaction.type == INTERACTION_COMMAND then
		return { type = RESPONSE_MESSAGE, data = interactions.status_panel(user) }
	end

	if interaction.type == INTERACTION_BUTTON then
		local panel = interactions.button_panels[interaction.data.custom_id]
		if not panel then
			error("unknown button " .. tostring(interaction.data.custom_id))
		end

		return { type = RESPONSE_UPDATE_MESSAGE, data = panel(user) }
	end

	error("unhandled interaction type " .. tostring(interaction.type))
end

---@return table response
function interactions.error_response()
	return {
		type = RESPONSE_MESSAGE,
		data = { content = "Something went wrong, try again in a moment.", flags = FLAG_EPHEMERAL },
	}
end

return interactions
