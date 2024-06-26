#pragma once
/**
 * @file safecall.hpp
 * @author Eric Mertens (emertens@gmail.com)
 * @brief Call Lua functions with backtrace reporting to stderr
 *
 */

#include <string_view>

struct lua_State;

/**
 * @brief Call a Lua function catching and reporting all errors
 *
 * @param L Lua interpreter handle
 * @param location Location to using in error reporting
 * @param args Number of function arguments on Lua stack
 * @return Result of lua_pcall
 */
int safecall(lua_State* L, std::string_view location, int args);
