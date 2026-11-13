-- masterserver -> server: when a player asks the master server for a ticket to join a server.
-- steam_id is a decimal string because SteamID64 doesn't fit in the Lua number type.
local packet = {}
packet.type = 66
packet.name = "auth"

---@param reader table data_reader over the body
---@return table fields
function packet.read(reader)
	return {
		account_id = reader:uint32(),
		phone_number = reader:uint32(),
		steam_id = reader:uint64(),
		auth_ticket = reader:uint32(),
		player_name = reader:string(32),
	}
end

---@param writer table data_writer
---@param data table fields
function packet.write(writer, data)
	writer:uint32(data.account_id)
	writer:uint32(data.phone_number)
	writer:uint64(data.steam_id)
	writer:uint32(data.auth_ticket)
	writer:string(data.player_name, 32)
end

return packet
