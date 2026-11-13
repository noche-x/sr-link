-- client -> server: server list ping.
local packet = {}
packet.type = 0
packet.name = "info_request"

---@param reader table data_reader over the body
---@return table fields
function packet.read(reader)
	return {
		version = reader:uint8(),
		timestamp = reader:uint32(),
	}
end

---@param writer table data_writer
---@param data table fields
function packet.write(writer, data)
	writer:uint8(data.version)
	writer:uint32(data.timestamp)
end

return packet
