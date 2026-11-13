local ffi = require("ffi")

local band, rshift = bit.band, bit.rshift

local data_reader = {}
data_reader.__index = data_reader

---@param data string packet body
---@return table reader
function data_reader.new(data)
	return setmetatable({ data = data, pos = 1, bit_pos = 0 }, data_reader)
end

---@param count number how many bits to read
---@return number value
function data_reader:bits(count)
	local value = 0
	for i = 0, count - 1 do
		local byte = self.data:byte(self.pos)
		if not byte then
			error("packet truncated", 0)
		end

		-- byte = 1010 0011, bit_pos = 1:  rshift -> 0101 0001,  band 1 -> 1
		local bit_value = band(rshift(byte, self.bit_pos), 1)
		-- the i-th bit read becomes bit i of the value
		value = value + bit_value * 2 ^ i
		self.bit_pos = self.bit_pos + 1

		if self.bit_pos == 8 then
			self.pos, self.bit_pos = self.pos + 1, 0
		end
	end

	return value
end

---@param count number how many bytes to read
---@return string bytes
function data_reader:bytes(count)
	if self.bit_pos ~= 0 then
		self.pos, self.bit_pos = self.pos + 1, 0
	end

	if self.pos + count - 1 > #self.data then
		error("packet truncated", 0)
	end

	local out = self.data:sub(self.pos, self.pos + count - 1)
	self.pos = self.pos + count

	return out
end

---@param size number size in bytes
---@return number value
function data_reader:unsigned(size)
	local bytes = self:bytes(size)
	local value = 0
	for i = size, 1, -1 do
		value = value * 256 + bytes:byte(i)
	end
	return value
end

---@return number value
function data_reader:uint8()
	return self:unsigned(1)
end

---@return number value
function data_reader:uint16()
	return self:unsigned(2)
end

---@return number value
function data_reader:uint32()
	return self:unsigned(4)
end

---@return string value decimal digits
function data_reader:uint64()
	local low = self:uint32()
	local high = self:uint32()
	local value = ffi.new("uint64_t", high) * 2 ^ 32 + low
	-- tostring gives "76561198000000000ULL"; drop the ULL suffix
	return tostring(value):sub(1, -4)
end

---@return string address dotted IPv4, stored as a uint32
function data_reader:ipv4()
	local ip = self:uint32()
	return ("%d.%d.%d.%d"):format(
		math.floor(ip / 2 ^ 24),
		math.floor(ip / 2 ^ 16) % 256,
		math.floor(ip / 2 ^ 8) % 256,
		ip % 256
	)
end

---@param length number size of the field in bytes
---@return string text the text before the first zero byte
function data_reader:string(length)
	return self:bytes(length):match("^[^%z]*")
end

return data_reader
