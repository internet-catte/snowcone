local M = {}

function M:keypress()
end

function M:render()
    local n = 0
    local rows = math.max(1, tty_height-2)
    local window = {}

    for _, entry in exits:each() do
        local y = (cliexit_n-1-n) % rows
        window[y] = entry
        n = n + 1
        if n >= rows-1 then break end
    end

    window[cliexit_n % rows] = 'divider'

    local last_time
    for y = 0, rows-1 do
        local entry = window[y]
        if entry == 'divider' then
            yellow()
            mvaddstr(y, 0, string.rep('·', tty_width))
        elseif entry then
            -- TIME
            local time = entry.time
            if time == last_time then
                mvaddstr(y, 0, '        ')
            else
                last_time = time

                local age = uptime - (entry.timestamp or 0)
                if age < 8 then
                    white()
                    mvaddstr(y, 0, string.sub(time, 1, 8-age))
                    cyan()
                    addstr(string.sub(time, 9-age, 8))
                else
                    cyan()
                    mvaddstr(y, 0, time)
                end
            end

            addstr('      ')
            local mask_color = ncurses.red
            -- MASK

            ncurses.attron(mask_color)
            addstr(entry.nick)
            black()
            addstr('!')
            ncurses.attron(mask_color)
            addstr(entry.user)
            black()
            addstr('@')
            ncurses.attron(mask_color)
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
            if show_reasons then
                if entry.reason == 'K-Lined' then
                    red()
                else
                    magenta()
                end
                mvaddstr(y, 80, string.sub(entry.reason, 1, 39))
            elseif entry.org then
                if entry.connected then
                    yellow()
                elseif entry.reason == 'K-Lined' then
                    red()
                else
                    magenta()
                end
                mvaddstr(y, 80, string.sub(entry.org, 1, 39))
            else
                yellow()
                mvaddstr(y, 80, entry.ip)
            end

            blue()
            local server = (servers[entry.server] or {}).alias
                        or string.sub(entry.server, 1, 2)
            mvaddstr(y, 120, server)

            -- Click handlers
            if entry.reason == 'K-Lined' then
                add_click(y, 0, tty_width, function()
                    entry_to_unkline(entry)
                end)
            else
                add_click(y, 0, tty_width, function()
                    entry_to_kline(entry)
                end)
            end
        end
    end

    draw_buttons()
    draw_global_load('CLIEXI', exit_tracker)
end

return M
