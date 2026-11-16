-- AES-256-GCM for the personal fields and Discord OAuth tokens stored in SQLite.
--
-- A stored value is "enc1:" followed by hex of iv (12 bytes), tag (16 bytes) and ciphertext.
local openssl = require("openssl")
local config = require("./config")

local PREFIX = "enc1:"
local IV_LENGTH = 12
local TAG_LENGTH = 16

local cipher = openssl.cipher
local gcm = cipher.get("aes-256-gcm")

local field_cipher = {}

---@param stored string a value read from the tokens table
---@return boolean encrypted false for tokens saved before encryption existed
function field_cipher.is_encrypted(stored)
	return stored:sub(1, #PREFIX) == PREFIX
end

---@param plaintext string
---@return string stored
function field_cipher.encrypt(plaintext)
	local iv = openssl.random(IV_LENGTH)
	local context = gcm:encrypt_new(config.token_key, iv)
	context:ctrl(cipher.EVP_CTRL_GCM_SET_IVLEN, IV_LENGTH)
	local encrypted = context:update(plaintext) .. context:final()
	local tag = context:ctrl(cipher.EVP_CTRL_GCM_GET_TAG, TAG_LENGTH)
	return PREFIX .. openssl.hex(iv .. tag .. encrypted)
end

---@param stored string
---@return string plaintext
function field_cipher.decrypt(stored)
	if not field_cipher.is_encrypted(stored) then
		error("value is not encrypted", 0)
	end

	local raw = openssl.hex(stored:sub(#PREFIX + 1), false)
	if not raw or #raw < IV_LENGTH + TAG_LENGTH then
		error("encrypted value is truncated", 0)
	end

	local iv = raw:sub(1, IV_LENGTH)
	local tag = raw:sub(IV_LENGTH + 1, IV_LENGTH + TAG_LENGTH)
	local context = gcm:decrypt_new(config.token_key, iv)
	context:ctrl(cipher.EVP_CTRL_GCM_SET_IVLEN, IV_LENGTH)
	context:ctrl(cipher.EVP_CTRL_GCM_SET_TAG, tag)
	local decrypted = context:update(raw:sub(IV_LENGTH + TAG_LENGTH + 1))
	local final = context:final()
	-- final fails when the tag does not match, which is a wrong key or changed data
	if not final then
		error("wrong key or corrupted data", 0)
	end

	return decrypted .. final
end

return field_cipher
