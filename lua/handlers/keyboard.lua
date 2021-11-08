local execute = {}

function execute.filter()
    filter = editor.rendered
    if filter == '' then
        filter = nil
    end
    editor:reset()
    input_mode = nil
end

local commands = require_ 'handlers.commands'
function execute.command()
    local command, args = string.match(editor.rendered, '^ *(%g*) *(.*)$')
    local impl = commands[command]
    if impl then
        editor:confirm()
        input_mode = nil
        status_message = ''

        local params = {}
        if impl.pattern(args, params) then
            local success, message = pcall(impl.implementation, table.unpack(params))
            if not success then
                status_message = message
            end
        else
            status_message = 'bad command arguments, expected: ' .. impl.spec
        end
    else
        if command ~= '' then
            status_message = 'unknown command'
        end
        editor:reset()
        input_mode = nil
    end
end

local function ctrl(x)
    return 0x1f & string.byte(x)
end

local function meta(x)
    return -string.byte(x)
end

-- Global keyboard mapping - can be overriden by views
local M = {
    --[[Esc]][0x1b] = function()
        reset_filter()
        status_message = nil
        editor:reset()
        input_mode = nil
        scroll = 0
    end,

    [ctrl 'L'] = ncurses.clear,
    [ctrl 'N'] = next_view,
    [ctrl 'P'] = prev_view,

    [0x7f] = function() if input_mode then editor:backspace() end end, -- Del
    [ctrl 'M'] = function() if input_mode then execute[input_mode]() end end, -- Enter
    [ctrl 'U'] = function() if input_mode then editor:kill_to_beg() end end,
    [ctrl 'K'] = function() if input_mode then editor:kill_to_end() end end,
    [ctrl 'A'] = function() if input_mode then editor:move_to_beg() end end,
    [ctrl 'E'] = function() if input_mode then editor:move_to_end() end end,
    [ctrl 'W'] = function() if input_mode then editor:kill_prev_word() end end,
    [meta 'd'] = function() if input_mode then editor:kill_next_word() end end,
    [ctrl 'B'] = function() if input_mode then editor:move_left() end end,
    [ctrl 'F'] = function() if input_mode then editor:move_right() end end,
    [ctrl 'Y'] = function() if input_mode then editor:paste() end end,
    [ctrl 'T'] = function() if input_mode then editor:swap() end end,
    [meta 'f'] = function() if input_mode then editor:move_next_word() end end,
    [meta 'b'] = function() if input_mode then editor:move_prev_word() end end,
    [-ncurses.KEY_LEFT     ] = function() if input_mode then editor:move_left() end end,
    [-ncurses.KEY_RIGHT    ] = function() if input_mode then editor:move_right() end end,
    [-ncurses.KEY_HOME     ] = function() if input_mode then editor:move_to_beg() end end,
    [-ncurses.KEY_END      ] = function() if input_mode then editor:move_to_end() end end,
    [-ncurses.KEY_BACKSPACE] = function() if input_mode then editor:backspace() end end,
    [-ncurses.KEY_DC       ] = function() if input_mode then editor:delete() end end,
    [-ncurses.KEY_UP       ] = function() if input_mode then editor:older_history() end end,
    [-ncurses.KEY_DOWN     ] = function() if input_mode then editor:newer_history() end end,

    [ctrl('C')] = function() snowcone.raise(2) end,
    [ctrl('Z')] = function() snowcone.raise(18) end,

    [ctrl('S')] = function()
        editor:reset()
        input_mode = 'filter'
    end,
    [string.byte('/')] = function()
        editor:reset()
        input_mode = 'command'
    end,
}

for i, v in ipairs(main_views) do
    M[-(ncurses.KEY_F1 - 1 + i)] = function() view = v end
end

return M
