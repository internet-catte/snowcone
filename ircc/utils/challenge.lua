local file <const> = require 'pl.file'
local Set  <const> = require 'pl.Set'
local N    <const> = require 'utils.numerics'
local send <const> = require 'utils.send'
local resolve_password <const> = require 'utils.resolve_password'

local commands1 <const> = Set{
    N.ERR_NOOPERHOST,
    N.RPL_RSACHALLENGE2,
    N.RPL_ENDOFRSACHALLENGE2,
    N.RPL_YOUREOPER,
}

local commands2 <const> = Set{
    N.RPL_YOUREOPER,
    N.ERR_PASSWDMISMATCH,
    N.ERR_NOOPERHOST,
}

return function(task)
    -- make sure we have a username and a key before bothering the server
    local user <const> = assert(configuration.oper_username, 'missing oper_username')
    local path <const> = assert(configuration.challenge_key, 'missing challenge_key')
    local rsa_key <const> = assert(file.read(path))
    local password <const> = resolve_password(configuration.challenge_password)
    local key <const> = assert(myopenssl.read_pem(rsa_key, true, password))

    local n = 0
    local chunks  <const> = {}

    send('CHALLENGE', user)
    while true do
        local irc     <const> = task:wait_irc(commands1)
        local command <const> = irc.command
        if command == N.RPL_RSACHALLENGE2 then
            n = n + 1
            chunks[n] = irc[2]
        elseif command == N.RPL_ENDOFRSACHALLENGE2 then
            break
        elseif command == N.RPL_YOUREOPER then
            status('challenge', 'already oper')
            return
        elseif command == N.ERR_NOOPERHOST then
            status('challenge', 'host mismatch')
            return
        end
    end

    local input    <const> = table.concat(chunks)
    local envelope <const> = assert(snowcone.from_base64(input), 'bad base64')
    local message  <const> = assert(key:decrypt(envelope, 'oaep'))
    local digest   <const> = myopenssl.get_digest('sha1'):digest(message)
    local response <const> = snowcone.to_base64(digest)

    send('CHALLENGE', '+' .. response)
    local irc     <const> = task:wait_irc(commands2)
    local command <const> = irc.command
    if command == N.RPL_YOUREOPER then
        status('challenge', "oper up")
    elseif command == N.ERR_PASSWDMISMATCH then
        status('challenge', 'key mismatch')
    elseif command == N.ERR_NOOPERHOST then
        status('challenge', 'host mismatch')
    end
end
