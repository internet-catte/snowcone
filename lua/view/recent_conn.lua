local addircstr = require 'utils.irc_formatting'
local scrub = require 'utils.scrub'
local drawing = require 'utils.drawing'

return function(data, label, tracker)

local M = {
    active = true,
    draw_status = function() end,
}

local function safematch(str, pat)
    local success, result = pcall(string.match, str, pat)
    return not success or result
end

local function show_entry(entry)
    local current_filter
    if input_mode == 'filter' then
        current_filter = editor.rendered
    else
        current_filter = filter
    end

    return
    (server_filter == nil or server_filter == entry.server) and
    (conn_filter == nil or conn_filter == not entry.reason) and
    (current_filter == nil or
     safematch(entry.mask, current_filter) or
     entry.gecos and safematch(entry.gecos, current_filter) or
     entry.org and safematch(entry.org, current_filter) or
     entry.asn and safematch('AS'..entry.asn, current_filter))
end

local handlers = {
    [-ncurses.KEY_PPAGE] = function()
        local elts = math.min(data.max, data.n)
        scroll = scroll + math.max(1, tty_height - 2)
        scroll = math.min(scroll, elts - tty_height + 2)
        scroll = math.max(scroll, 0)
    end,
    [-ncurses.KEY_NPAGE] = function()
        scroll = scroll - math.max(1, tty_height - 2)
        scroll = math.max(scroll, 0)
    end,
    [string.byte('q')] = function() conn_filter = true  end,
    [string.byte('w')] = function() conn_filter = false end,
    [string.byte('e')] = function() conn_filter = nil   end,
    [string.byte('k')] = function()
        if staged_action.action == 'kline' then
            snowcone.send_irc(
                string.format('KLINE %s %s :%s\r\n',
                    kline_durations[kline_duration][2],
                    staged_action.mask,
                    kline_reasons[kline_reason][2]
                )
            )
            staged_action = nil
        end
    end,
}

function M:keypress(key)
    local f = handlers[key]
    if f then
        f()
        draw()
    end
end

local rotating_window = require_ 'utils.rotating_window'

function M:render()
    local clear_line = string.rep(' ', tty_width)
    local last_time
    local rows = math.max(1, tty_height-2)

    local window = rotating_window(data, rows, show_entry)

    for y = 0, rows-1 do
        ncurses.move(y, 0)
        local entry = window[y+1]
        if entry == 'divider' then
            yellow()
            addstr(os.date '!%H:%M:%S' .. string.rep('·', tty_width - 8))
            normal()
            last_time = nil
        elseif entry then
            -- TIME
            local time = entry.time
            if time == last_time then
                mvaddstr(y, 0, '        ')
            else
                last_time = time
                drawing.fade_time(entry.timestamp, time)
            end

            local mask_color = entry.reason and ncurses.red or ncurses.green

            -- FILTERS and RECONNECT counter
            if entry.filters then
                ncurses.colorset(mask_color)
                addstr(string.format(' %3d!', entry.filters))
            elseif entry.count then
                if entry.count < 2 then
                    black()
                end
                addstr(string.format(" %4d", entry.count))
            end

            if entry.mark then
                if type(entry.mark) == 'number' then ncurses.colorset(entry.mark) end
                addstr('◆')
            else
                addstr(' ')
            end

            -- MASK
            if highlight and (
                highlight_plain     and highlight == entry.mask or
                not highlight_plain and string.match(entry.mask, highlight)) then
                    bold()
            end

            ncurses.colorset(mask_color)
            mvaddstr(y, 14, entry.nick)
            black()
            addstr('!')
            ncurses.colorset(mask_color)
            addstr(entry.user)
            black()
            addstr('@')
            ncurses.colorset(mask_color)
            local maxwidth = 63 - #entry.nick - #entry.user
            if #entry.host <= maxwidth then
                addstr(entry.host)
                normal()
            else
                addstr(string.sub(entry.host, 1, maxwidth-1))
                normal()
                addstr('…')
            end

            -- IP or REASON
            if not entry.reason then
                yellow()
            elseif entry.reason == 'K-Lined' then
                red()
            else
                magenta()
            end

            if show_reasons == 'reason' and entry.reason then
                mvaddstr(y, 80, string.sub(scrub(entry.reason), 1, 39))
            elseif show_reasons == 'asn' and entry.asn then
                mvaddstr(y, 80, string.format("AS%-6d %-30.30s", entry.asn, entry.org or ''))
            elseif show_reasons ~= 'ip' and entry.org then
                mvaddstr(y, 80, string.sub(entry.org, 1, 39))
            else
                mvaddstr(y, 80, entry.ip)
            end

            -- SERVER
            blue()
            local alias = (servers.servers[entry.server] or {}).alias
            if alias then
                mvaddstr(y, 120, string.format('%-2.2s ', alias))
            else
                mvaddstr(y, 120, string.format('%-3.3s ', entry.server))
            end

            -- GECOS or ACCOUNT
            normal()
            if entry.account == '*' then
                cyan()
                addstr('· ')
            elseif entry.account then
                cyan()
                addstr(entry.account .. ' ')
            end

            if entry.gecos then
                addircstr(entry.gecos)
            end

            -- Click handlers
            if entry.reason == 'K-Lined' then
                add_click(y, 14, 79, function()
                    entry_to_unkline(entry)
                    highlight = entry.mask
                    highlight_plain = true
                end)
            else
                add_click(y, 14, 79, function()
                    entry_to_kline(entry)
                    highlight = entry.mask
                    highlight_plain = true
                end)
            end

            add_click(y, 120, 122, function()
                server_filter = entry.server
            end)

            local y_end = ncurses.getyx()
            for i = y+1,y_end do
                mvaddstr(i, 0, clear_line)
            end
        end
    end

    draw_buttons()

    draw_global_load(label, tracker)

    if input_mode == nil then
        if conn_filter ~= nil then
            if conn_filter then
                green() addstr(' LIVE')
            else
                red() addstr(' DEAD')
            end
            normal()
        end
        if server_filter ~= nil then
            yellow() addstr(' SERVER')
            normal()
        end
    end
end

return M

end
