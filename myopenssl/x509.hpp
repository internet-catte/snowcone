#pragma once

struct lua_State;

namespace myopenssl
{
auto l_new_x509(lua_State* const L) -> int;
}