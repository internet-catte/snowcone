local class = require 'pl.class'
local OrderedMap = require 'components.OrderedMap'

local M = class()
M._name = 'Buffer'

local maxhistory = 1000

function M:_init(name)
    self.name = name
    self.messages = OrderedMap(maxhistory)
    self.activity = 0
    self.mention = false
end

function M:look()
    self.activity = 0 -- mark everything as seen
    self.mention = false -- forget mentions
end

return M
