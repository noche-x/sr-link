-- client -> server: join request.
local packet = {}
packet.type = 2
packet.name = "join_request"

---@param reader table data_reader over the body
---@return table fields
function packet.read(reader)
	return {
		version = reader:uint8(),
		account_id = reader:uint32(),
		auth_ticket = reader:uint32(),
		player_name = reader:string(32),
		avatar_info = reader:uint32(),
		password = reader:string(32),
		protocol_version = reader:uint8(),
		phone_number = reader:uint32(),
	}
end

---@param writer table data_writer
---@param data table fields
function packet.write(writer, data)
	writer:uint8(data.version)
	writer:uint32(data.account_id)
	writer:uint32(data.auth_ticket)
	writer:string(data.player_name, 32)
	writer:uint32(data.avatar_info)
	writer:string(data.password, 32)
	writer:uint8(data.protocol_version)
	writer:uint32(data.phone_number)
end

return packet
