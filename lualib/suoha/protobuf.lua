local protobuf = {}

local function read_varint(data, pos)
	local result = 0
	local shift = 0
	while true do
		local b = data:byte(pos)
		if not b then
			error("truncated varint")
		end
		pos = pos + 1
		result = result | ((b & 0x7f) << shift)
		if (b & 0x80) == 0 then
			return result, pos
		end
		shift = shift + 7
		if shift > 63 then
			error("malformed varint")
		end
	end
end

local function write_varint(value)
	value = value or 0
	local out = {}
	repeat
		local b = value & 0x7f
		value = value >> 7
		if value ~= 0 then
			b = b | 0x80
		end
		out[#out + 1] = string.char(b)
	until value == 0
	return table.concat(out)
end

local function skip_field(data, pos, wire_type)
	if wire_type == 0 then
		local _, next_pos = read_varint(data, pos)
		return next_pos
	elseif wire_type == 1 then
		return pos + 8
	elseif wire_type == 2 then
		local len
		len, pos = read_varint(data, pos)
		return pos + len
	elseif wire_type == 5 then
		return pos + 4
	end
	error("unsupported protobuf wire type " .. tostring(wire_type))
end

function protobuf.decode(schema, data)
	local obj = {}
	local pos = 1
	local size = #data
	while pos <= size do
		local tag
		tag, pos = read_varint(data, pos)
		local field_no = tag >> 3
		local wire_type = tag & 0x7
		local field = schema[field_no]
		if not field then
			pos = skip_field(data, pos, wire_type)
		elseif field.type == "string" or field.type == "bytes" or field.type == "message" then
			if wire_type ~= 2 then
				error("invalid wire type for field " .. field.name)
			end
			local len
			len, pos = read_varint(data, pos)
			local value = data:sub(pos, pos + len - 1)
			pos = pos + len
			if field.type == "message" then
				value = protobuf.decode(field.schema, value)
			end
			obj[field.name] = value
		elseif field.type == "bool" then
			if wire_type ~= 0 then
				error("invalid wire type for field " .. field.name)
			end
			local value
			value, pos = read_varint(data, pos)
			obj[field.name] = value ~= 0
		elseif field.type == "int32" or field.type == "int64" then
			if wire_type ~= 0 then
				error("invalid wire type for field " .. field.name)
			end
			local value
			value, pos = read_varint(data, pos)
			obj[field.name] = value
		else
			error("unsupported protobuf field type " .. tostring(field.type))
		end
	end
	return obj
end

local function should_write(field, value)
	if value == nil then
		return false
	end
	if field.type == "bool" then
		return value
	end
	if field.type == "int32" or field.type == "int64" then
		return value ~= 0
	end
	if field.type == "string" or field.type == "bytes" then
		return value ~= ""
	end
	if field.type == "message" then
		return true
	end
	return false
end

function protobuf.encode(schema, obj)
	local out = {}
	for field_no = 1, 2048 do
		local field = schema[field_no]
		if field then
			local value = obj[field.name]
			if should_write(field, value) then
				if field.type == "string" or field.type == "bytes" then
					out[#out + 1] = write_varint((field_no << 3) | 2)
					out[#out + 1] = write_varint(#value)
					out[#out + 1] = value
				elseif field.type == "message" then
					local bytes = protobuf.encode(field.schema, value)
					out[#out + 1] = write_varint((field_no << 3) | 2)
					out[#out + 1] = write_varint(#bytes)
					out[#out + 1] = bytes
				elseif field.type == "bool" then
					out[#out + 1] = write_varint(field_no << 3)
					out[#out + 1] = write_varint(value and 1 or 0)
				elseif field.type == "int32" or field.type == "int64" then
					out[#out + 1] = write_varint(field_no << 3)
					out[#out + 1] = write_varint(value)
				end
			end
		end
	end
	return table.concat(out)
end

return protobuf
