-- Library imports
local Set    = require 'pl.Set'
local tablex = require 'pl.tablex'
local pretty = require 'pl.pretty'
local path   = require 'pl.path'
local file   = require 'pl.file'
local dir    = require 'pl.dir'

if not uptime then
    require 'pl.stringx'.import()
    require 'pl.app'.require_here()
end

addstr = ncurses.addstr
mvaddstr = ncurses.mvaddstr

function normal()       ncurses.attrset(ncurses.WA_NORMAL, 0)   end
function bold()         ncurses.attron(ncurses.WA_BOLD)         end
function bold_()        ncurses.attroff(ncurses.WA_BOLD)        end
function reversevideo() ncurses.attron(ncurses.WA_REVERSE)      end
function reversevideo_()ncurses.attroff(ncurses.WA_REVERSE)     end
function underline()    ncurses.attron(ncurses.WA_UNDERLINE)    end
function underline_()   ncurses.attroff(ncurses.WA_UNDERLINE)   end
function red()          ncurses.colorset(ncurses.red)           end
function green()        ncurses.colorset(ncurses.green)         end
function blue()         ncurses.colorset(ncurses.blue)          end
function cyan()         ncurses.colorset(ncurses.cyan)          end
function black()        ncurses.colorset(ncurses.black)         end
function magenta()      ncurses.colorset(ncurses.magenta)       end
function yellow()       ncurses.colorset(ncurses.yellow)        end
function white()        ncurses.colorset(ncurses.white)         end

function require_(name)
    package.loaded[name] = nil
    return require(name)
end

-- Local modules ======================================================

local NetTracker         = require_ 'components.NetTracker'
local Editor             = require_ 'components.Editor'
local LoadTracker        = require_ 'components.LoadTracker'
local OrderedMap         = require_ 'components.OrderedMap'
local libera_masks       = require_ 'utils.libera_masks'
local addircstr          = require_ 'utils.irc_formatting'
local drawing            = require_ 'utils.drawing'
local utils_time         = require_ 'utils.time'
local send               = require_ 'utils.send'
local irc_registration   = require_ 'utils.irc_registration'

-- Validate configuration =============================================

if string.match(configuration.irc_nick, '[ \n\r]') then
    error 'Invalid character in nickname'
end

if configuration.irc_user and string.match(configuration.irc_user, '[ \n\r]') then
    error 'Invalid character in username'
end

if configuration.irc_gecos and string.match(configuration.irc_gecos, '[\n\r]') then
    error 'Invalid character in GECOS'
end

if configuration.irc_pass and string.match(configuration.irc_pass, '[\n\r]') then
    error 'Invalid character in server password'
end

if configuration.irc_oper_username and string.match(configuration.irc_oper_username, '[ \n\r]') then
    error 'Invalid character in operator username'
end

if configuration.irc_capabilities and string.match(configuration.irc_capabilities, '[\n\r]') then
    error 'Invalid character in capabilities'
end

-- Load network configuration =========================================

local xdgconf = os.getenv 'XDG_CONFIG_HOME'
if not xdgconf then
    xdgconf = path.join(os.getenv 'HOME', '.config')
end

do
    servers = { servers = {}, regions = {},
        kline_reasons = { 'banned', "You are banned."} }
    local conf = configuration.network_filename
    if not conf then
        conf = path.join(xdgconf, "snowcone", "servers.lua")
    end
    local txt, file_err = file.read(conf)
    if txt then
        local val, lua_err = pretty.read(txt)
        if val then
            servers = val
        else
            error('Failed to parse ' .. conf .. '\n' .. lua_err)
        end
    elseif configuration.network_filename then
        error(file_err)
    end
end

-- Global state =======================================================

function reset_filter()
    filter = nil
    server_filter = nil
    conn_filter = nil
    highlight = nil
    highlight_plain = false
    staged_action = nil
end

local defaults = {
    -- state
    users = OrderedMap(1000, snowcone.irccase),
    exits = OrderedMap(1000, snowcone.irccase),
    messages = OrderedMap(1000),
    status_messages = OrderedMap(100),
    klines = OrderedMap(1000),
    new_channels = OrderedMap(100, snowcone.irccase),
    kline_tracker = LoadTracker(),
    conn_tracker = LoadTracker(),
    exit_tracker = LoadTracker(),
    net_trackers = {},
    view = 'cliconn',
    uptime = 0, -- seconds since startup
    liveness = 0, -- timestamp of last irc receipt
    mrs = {},
    scroll = 0,
    filter_tracker = LoadTracker(),
    population = {},
    links = {},
    upstream = {},
    status_message = '',
    irc_state = {},
    uv_resources = {},
    editor = Editor(),
    versions = {},
    uptimes = {},
    draw_suspend = 'no', -- no: draw normally; eligible: don't draw; suspended: a draw is needed

    -- settings
    show_reasons = 'reason',
    kline_duration = '1d',
    kline_reason = 1,
    trust_uname = false,
    server_ordering = 'name',
    server_descending = false,
    watches = {},
}

function initialize()
    tablex.update(_G, defaults)
    reset_filter()
end

for k,v in pairs(defaults) do
    if not _G[k] then
        _G[k] = v
    end
end

-- Prepopulate the server list
for server, _ in pairs(servers.servers or {}) do
    conn_tracker:track(server, 0)
    exit_tracker:track(server, 0)
end

--  Helper functions ==================================================

function ctrl(x)
    return 0x1f & string.byte(x)
end

function meta(x)
    return -string.byte(x)
end

function status(category, fmt, ...)
    local text = string.format(fmt, ...)
    status_messages:insert(nil, {
        time = os.date("!%H:%M:%S"),
        text = text,
        category = category,
    })
    status_message = text
end

-- Kline logic ========================================================

kline_durations = {'4h','1d','3d'}

function entry_to_kline(entry)
    prepare_kline(entry.nick, entry.user, entry.host, entry.ip)
end

function prepare_kline(nick, user, host, ip)
    local success, mask = pcall(libera_masks, user, ip, host, trust_uname)
    if success then
        staged_action = {
            action = 'kline',
            mask = mask,
            nick = nick,
            user = user,
            host = host,
            ip = ip,
        }
        send('TESTMASK', mask)
    else
        status('kline', '%s', mask)
        staged_action = nil
    end
end

function entry_to_unkline(entry)
    local mask = entry.user .. '@' .. entry.ip
    send('TESTKLINE', mask)
    staged_action = {action = 'unkline', nick = entry.nick}
end

local function kline_ready()
    return staged_action ~= nil
       and staged_action.action == 'kline'
end

local function undline_ready()
    return staged_action ~= nil
       and staged_action.action == 'undline'
       and staged_action.mask ~= nil
end

local function unkline_ready()
    return staged_action ~= nil
       and staged_action.action == 'unkline'
       and staged_action.mask ~= nil
end

-- Mouse logic ========================================================

local clicks = {}

function add_click(y, lo, hi, action)
    local list = clicks[y]
    local entry = {lo=lo, hi=hi, action=action}
    if list then
        table.insert(list, entry)
    else
        clicks[y] = {entry}
    end
end

function add_button(text, action, plain)
    local y1,x1 = ncurses.getyx()
    if not plain then reversevideo() end
    addstr(text)
    if not plain then reversevideo_() end
    local _, x2 = ncurses.getyx()
    add_click(y1, x1, x2, action)
end

-- Screen rendering ===================================================

function draw_global_load(title, tracker)
    local titlecolor = ncurses.white
    if kline_ready() then
        titlecolor = ncurses.red
    end

    ncurses.colorset(ncurses.black, titlecolor)
    mvaddstr(tty_height-1, 0, string.format('%-8.8s', view))

    if input_mode then
        ncurses.colorset(titlecolor, ncurses.blue)
        addstr('')
        ncurses.colorset(ncurses.white, ncurses.blue)
        addstr(input_mode)
        blue()
        addstr('')

        if 1 < editor.first then
            yellow()
            addstr('…')
            blue()
        else
            addstr(' ')
        end

        if input_mode == 'filter' and not pcall(string.match, '', editor.rendered) then
            red()
        end

        local y0, x0 = ncurses.getyx()

        addstr(editor.before_cursor)

        -- cursor overflow: clear and redraw
        local y1, x1 = ncurses.getyx()
        if x1 == tty_width - 1 then
            yellow()
            mvaddstr(y0, x0-1, '…' .. string.rep(' ', tty_width)) -- erase line
            blue()
            editor:overflow()
            mvaddstr(y0, x0, editor.before_cursor)
            y1, x1 = ncurses.getyx()
        end

        addstr(editor.at_cursor)
        ncurses.move(y1, x1)
        ncurses.cursset(1)
    else
        ncurses.colorset(titlecolor)
        addstr('')
        magenta()
        addstr(title .. '')
        drawing.draw_load(tracker.global)
        normal()

        views[view]:draw_status()

        if status_message then
            addircstr(' ' .. status_message)
        end

        if scroll ~= 0 then
            addstr(string.format(' SCROLL %d', scroll))
        end

        if filter ~= nil then
            yellow()
            addstr(' FILTER ')
            normal()
            addstr(string.format('%q', filter))
        end

        add_click(tty_height-1, 0, 9, next_view)
        ncurses.cursset(0)
    end
end

function draw_buttons()
    mvaddstr(tty_height-2, 0, ' ')
    bold()

    black()
    if show_reasons == 'reason' then

        add_button('[ REASON ]', function() show_reasons = 'org' end)
    elseif show_reasons == 'org' then
        add_button('[  ORG   ]', function() show_reasons = 'asn' end)
    elseif show_reasons == 'asn' then
        add_button('[  ASN   ]', function() show_reasons = 'ip' end)
    else
        add_button('[   IP   ]', function() show_reasons = 'reason' end)
    end
    addstr ' '

    if filter then
        blue()
        add_button('[ CLEAR FILTER ]', function()
            filter = nil
        end)
        addstr ' '
    end

    cyan()
    add_button('[ ' .. kline_duration .. ' ]', function()
        local i = tablex.find(kline_durations, kline_duration) or 0
        kline_duration = kline_durations[i % #kline_durations + 1]
    end)
    addstr ' '

    blue()
    add_button(trust_uname and '[ ~ ]' or '[ = ]', function()
        trust_uname = not trust_uname
        if staged_action and staged_action.action == 'kline' then
            prepare_kline(staged_action.nick, staged_action.user, staged_action.host, staged_action.ip)
        end
    end)
    addstr ' '

    magenta()
    local blacklist_text =
        string.format('[ %-7s ]', servers.kline_reasons[kline_reason][1])
    add_button(blacklist_text, function()
        kline_reason = kline_reason % #servers.kline_reasons + 1
    end)
    addstr ' '

    if kline_ready() then
        green()
        add_button('[ CANCEL KLINE ]', function()
            staged_action = nil
            highlight = nil
            highlight_plain = nil
        end)

        addstr(' ')
        red()
        local klineText = string.format('[ KLINE %s %s %s ]',
            staged_action.count and tostring(staged_action.count) or '?',
            staged_action.nick or '*',
            staged_action.mask)
        add_button(klineText, function()
            send('KLINE',
                utils_time.parse_duration(kline_duration),
                staged_action.mask,
                servers.kline_reasons[kline_reason][2]
            )
            staged_action = nil
        end)

    elseif unkline_ready() then
        green()
        add_button('[ CANCEL UNKLINE ]', function()
            staged_action = nil
            highlight = nil
            highlight_plain = nil
        end)

        addstr(' ')
        yellow()
        local klineText = string.format('[ UNKLINE %s %s ]',
            staged_action.nick or '*',
            staged_action.mask or '?')
        add_button(klineText, function()
            if staged_action.mask then
                send('UNKLINE', staged_action.mask)
            end
            staged_action = nil
        end)
    elseif undline_ready() then
        green()
        add_button('[ CANCEL UNDLINE ]', function()
            staged_action = nil
        end)

        addstr(' ')
        yellow()
        local dlineText = string.format('[ UNDLINE %s ]', staged_action.mask)
        add_button(dlineText, function()
            send('UNDLINE', staged_action.mask)
            staged_action = nil
        end)
    end

    normal()
end

local view_recent_conn = require_ 'view.recent_conn'
local view_server_load = require_ 'view.server_load'
local view_simple_load = require_ 'view.simple_load'
views = {
    cliconn = view_recent_conn(users, 'cliconn', conn_tracker),
    connload = view_server_load('Connection History', 'cliconn', ncurses.green, conn_tracker),
    cliexit = view_recent_conn(exits, 'cliexit', exit_tracker),
    exitload = view_server_load('Disconnection History', 'cliexit', ncurses.red, exit_tracker),
    netcount = require_ 'view.netcount',
    bans = require_ 'view.bans',
    stats = require_ 'view.stats',
    repeats = require_ 'view.repeats',
    banload = view_simple_load('banload', 'K-Liner', 'KLINES', 'K-Line History', kline_tracker),
    spamload = view_simple_load('spamload', 'Server', 'FILTERS', 'Filter History', filter_tracker),
    console = require_ 'view.console',
    channels = require_ 'view.channels',
    status = require_ 'view.status',
    plugins = require_ 'view.plugins',
    help = require_ 'view.help',
}

main_views = {'cliconn', 'connload', 'cliexit', 'exitload', 'bans', 'channels', 'netcount', 'console'}

function next_view()
    local current = tablex.find(main_views, view)
    if current then
        view = main_views[current % #main_views + 1]
    else
        view = main_views[1]
    end
end

function prev_view()
    local current = tablex.find(main_views, view)
    if current then
        view = main_views[(current - 2) % #main_views + 1]
    else
        view = main_views[1]
    end
end

function draw()
    if draw_suspend ~= 'no' then
        draw_suspend = 'suspended'
        return
    end
    clicks = {}
    ncurses.erase()
    normal()
    views[view]:render()
    ncurses.refresh()
end

-- Network Tracker Logic ==============================================

function add_network_tracker(name, mask)
    local address, prefix, b

    address, prefix = string.match(mask, '^([^/]*)/(%d+)$')
    if address then
        b = assert(snowcone.pton(address))
        prefix = math.tointeger(prefix)
    else
        b = assert(snowcone.pton(mask))
        prefix = 8 * #b
    end

    if not net_trackers[name] then
        net_trackers[name] = NetTracker()
    end

    net_trackers[name]:track(mask, b, prefix)
    if irc_state.oper then
        send('TESTMASK', '*@' .. mask)
    end
end

for name, masks in pairs(servers.net_tracks or {}) do
    if not net_trackers[name] then
        for _, mask in ipairs(masks) do
            add_network_tracker(name, mask)
        end
    end
end

-- IRC Registration Logic =============================================

function counter_sync_commands()
    send('MAP')
    send('LINKS')
    for _, entry in pairs(net_trackers) do
        for label, _ in pairs(entry.masks) do
            send('TESTMASK', '*@' .. label)
        end
    end
end

-- Timers =============================================================

local function refresh_rotations()
    for label, entry in pairs(servers.regions or {}) do
        snowcone.dnslookup(entry.hostname, function(addrs, reason)
            mrs[label] = Set(addrs)
            if reason then
                status('dns', '%s: %s', entry.hostname, reason)
            end
        end)
    end
end

if not uv_resources.rotations_timer then
    uv_resources.rotations_timer = snowcone.newtimer()
    uv_resources.rotations_timer:start(0, 30000, function()
        refresh_rotations()
    end)
end

if not uv_resources.tick_timer then
    uv_resources.tick_timer = snowcone.newtimer()
    uv_resources.tick_timer:start(1000, 1000, function()
        uptime = uptime + 1
        if irc_state.connected and uptime == liveness + 30 then
            send('PING', 'snowcone')
        end

        conn_tracker:tick()
        exit_tracker:tick()
        kline_tracker:tick()
        filter_tracker:tick()
        draw()
    end)
end

function quit()
    snowcone.shutdown()
    for _, handle in pairs(uv_resources) do
        handle:close()
    end
    send('QUIT')
    snowcone.send_irc(nil)
end

-- Load plugins

do
    plugins = {}
    local plugin_dir = path.join(xdgconf, 'snowcone', 'plugins')
    local success, paths = pcall(dir.getfiles, plugin_dir, '*.lua')

    if success then
        for _, plugin_path in ipairs(paths) do
            local plugin, load_error = loadfile(plugin_path)

            local state_path = plugin_path .. ".dat"
            local state_body = file.read(state_path)
            local state = state_body and pretty.read(state_body)

            local function save(new_state)
                file.write(state_path, pretty.write(new_state))
            end

            if plugin then
                local started, result = pcall(plugin, state, save)
                if started then
                    table.insert(plugins, result)
                else
                    status('plugin', 'startup: %s', result)
                end
            else
                status('plugin', 'loadfile: %s', load_error)
            end
        end
    end
end

-- Command handlers ===================================================

commands = require_ 'handlers.commands'

for _, plugin in ipairs(plugins) do
    local plugin_commands = plugin.commands
    if plugin_commands ~= nil then
        tablex.update(commands, plugin_commands)
    end
end

-- Callback Logic =====================================================

local M = {}

local irc_handlers = require_ 'handlers.irc'
function M.on_irc(irc)
    local time
    if irc.tags.time then
        time = string.match(irc.tags.time, '^%d%d%d%d%-%d%d%-%d%dT(%d%d:%d%d:%d%d)%.%d%d%dZ$')
    end
    if time == nil then
        time = os.date '!%H:%M:%S'
    end
    irc.time = time
    irc.timestamp = uptime

    messages:insert(true, irc)
    liveness = uptime
    local f = irc_handlers[irc.command]
    if f then
        f(irc)
    end

    for _, plugin in ipairs(plugins) do
        local h = plugin.irc
        if h then
            local success, err = pcall(h, irc)
            if not success then
                status(plugin.name, 'irc handler error: ' .. tostring(err))
            end
        end
    end
end

function M.on_irc_err(msg)
    status('socat', '%s', msg)
end

local key_handlers = require_ 'handlers.keyboard'
function M.on_keyboard(key)
    -- buffer text editing
    if input_mode and 0x20 <= key and (key < 0x7f or 0xa0 <= key) then
        editor:add(key)
        draw()
        return
    end

    -- global key handlers
    local f = key_handlers[key]
    if f then
        f()
        draw()
        return
    end

    -- view-specific key handlers
    views[view]:keypress(key)
end

function M.on_paste(paste)
    draw_suspend = 'eligible'
    for _, c in utf8.codes(paste) do
        M.on_keyboard(c)
    end
    if draw_suspend == 'suspended' then
        draw_suspend = 'no'
        draw()
    end
end

function M.on_mouse(y, x)
    for _, button in ipairs(clicks[y] or {}) do
        if button.lo <= x and x < button.hi then
            button.action()
            draw()
        end
    end
end

function M.on_connect()
    status('irc', 'connecting')
    irc_registration()
end

function M.on_disconnect()
    irc_state = {}
    status('irc', 'disconnected')
end

function M.print(str)
    status('print', str)
end

snowcone.setmodule(M)
