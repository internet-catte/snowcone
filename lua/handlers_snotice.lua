-- Logic for parsed snotices

local function count_ip(address, delta)
    if next(net_trackers) then
    dnslookup(address, function(_, baddrs, _)
        if baddrs then
            local baddr = baddrs[1]
            for _, x in ipairs(net_trackers) do
                if x:match(baddr) then
                    x.count = x.count + delta
                end
            end
        end
    end)
    end
end

local M = {}

function M.connect(ev)
    local key = ev.nick
    local server = ev.server

    local prev = users:lookup(key)
    local entry = {
        server = ev.server,
        gecos = ev.gecos,
        host = ev.host,
        user = ev.user,
        nick = ev.nick,
        account = ev.account,
        ip = ev.ip,
        org = ip_org(ev.ip),
        time = ev.time,
        count = prev and prev.count+1 or 1,
        mask = ev.nick .. '!' .. ev.user .. '@' .. ev.host .. ' ' .. ev.gecos,
        timestamp = uptime,
    }
    users:insert(key, entry)

    while users.n > history do
        users:pop_back()
    end
    conn_tracker:track(server)
    if show_entry(entry) then
        clicon_n = clicon_n + 1
    end

    local pop = population[ev.server]
    if pop then
        population[ev.server] = pop + 1
    end

    count_ip(ev.ip, 1)
end

function M.disconnect(ev)
    local key = ev.nick
    local entry = users:lookup(key)

    exit_tracker:track(ev.server)
    local pop = population[ev.server]
    if pop then
        population[ev.server] = pop - 1
    end

    if entry then
        entry.reason = ev.reason
        draw()
    end

    cliexit_n = cliexit_n + 1
    exits:insert(true, {
        nick = ev.nick,
        user = ev.user,
        host = ev.host,
        ip = ev.ip,
        reason = ev.reason,
        timestamp = uptime,
        time = ev.time,
        server = ev.server,
        org = ip_org(ev.ip),
        mask = ev.nick .. '!' .. ev.user .. '@' .. ev.host,
        gecos = (entry or {}).gecos,
    })
    while exits.n > history do
        exits:pop_back()
    end

    count_ip(ev.ip, -1)
end

function M.nick(ev)
    local user = users:lookup(ev.old)
    if user then
        user.nick = ev.new
        users:rekey(ev.old, ev.new)
    end
end

function M.kline(ev)
    kline_tracker:track(ev.nick)
end

function M.filter(ev)
    filter_tracker:track(ev.server)
    local mask = ev.nick
    local user = users:lookup(mask)
    if user then
        user.filters = (user.filters or 0) + 1
    end
end

function M.netjoin(ev)
    send_irc(counter_sync_commands())
    status_message = 'netjoin ' .. ev.server2
end

function M.netsplit(ev)
    send_irc(counter_sync_commands())
    status_message = 'netsplit ' .. ev.server2 .. ' ('.. ev.reason .. ')'
end

return M
