-- server -> masterserver: keepalive/heartbeat.
-- masterserver -> server: server ip address.
local packet = {}
packet.type = 64
packet.name = "master_ping"

---@param reader table data_reader over the body
---@return table fields
function packet.read(reader)
	return {
		ip = reader:ipv4(),
		port = reader:uint16(),
	}
end

---@param writer table data_writer
---@param data table unused
function packet.write(writer, data)
end

return packet
