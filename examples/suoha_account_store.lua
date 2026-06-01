local skynet = require "skynet"

local CMD = {}

local next_player_id = 100001
local accounts = {
	guest = {
		account = "guest",
		password = "password",
		token = "guest-token",
		player_id = 100000,
		name = "guest",
		lang = "zh_CN",
		level = 1,
		gold = 0,
		diamond = 0,
		physical = 100,
		reconnect_sign = "guest-reconnect",
		role_created = true,
	},
}

local online = {}

local function new_reconnect_sign(account, player_id)
	return string.format("%s-%d-%d", account, player_id, skynet.now())
end

function CMD.register(account, password)
	if account == nil or account == "" or password == nil or password == "" then
		return nil, "bad_param"
	end
	if accounts[account] then
		return nil, "exists"
	end
	local player_id = next_player_id
	next_player_id = next_player_id + 1
	accounts[account] = {
		account = account,
		password = password,
		token = account .. "-token",
		player_id = player_id,
		name = account,
		lang = "zh_CN",
		level = 1,
		gold = 0,
		diamond = 0,
		physical = 100,
		reconnect_sign = new_reconnect_sign(account, player_id),
		role_created = true,
	}
	return accounts[account]
end

function CMD.login(account, password, is_token, agent, fd, lang, network, device_id)
	local a = accounts[account]
	if not a then
		return nil, "not_register"
	end
	if is_token then
		if password ~= a.token then
			return nil, "token_error"
		end
	elseif password ~= a.password then
		return nil, "password_error"
	end
	if lang and lang ~= "" then
		a.lang = lang
	end
	if network and network ~= "" then
		a.network = network
	end
	if device_id and device_id ~= "" then
		a.device_id = device_id
	end
	a.reconnect_sign = new_reconnect_sign(account, a.player_id)
	local old = online[account]
	online[account] = { agent = agent, fd = fd }
	return a, nil, old
end

function CMD.reconnect(account, player_id, sig, agent, fd, network)
	local a = accounts[account]
	if not a then
		return nil, "not_register"
	end
	if a.player_id ~= player_id or a.reconnect_sign ~= sig then
		return nil, "reconnect_error"
	end
	if network and network ~= "" then
		a.network = network
	end
	a.reconnect_sign = new_reconnect_sign(account, a.player_id)
	local old = online[account]
	online[account] = { agent = agent, fd = fd }
	return a, nil, old
end

function CMD.logout(account, agent)
	local old = online[account]
	if old and old.agent == agent then
		online[account] = nil
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, cmd, ...)
		local f = assert(CMD[cmd])
		skynet.retpack(f(...))
	end)
end)
