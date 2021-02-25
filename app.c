#include <lua5.3/lua.h>
#include <lua5.3/lauxlib.h>
#include <lua5.3/lualib.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

#include "app.h"

static char logic_module;

struct app
{
    lua_State *L;
    char const *logic_filename;
    void (*write)(char *, size_t);
};

static int app_print(lua_State *L)
{
    int n = lua_gettop(L);  /* number of arguments */
    struct app *a = lua_touserdata(L, lua_upvalueindex(1));

    luaL_Buffer b;
    luaL_buffinit(L, &b);

    for (int i = 1; i <= n; i++) {
            (void)luaL_tolstring(L, i, NULL); // leaves string on stack
            luaL_addvalue(&b); // consumes string
            luaL_addchar(&b, i==n ? '\n' : '\t');
    }

    luaL_pushresult(&b);
    size_t msglen;
    char const* msg = lua_tolstring(L, -1, &msglen);
    
    if (a->write)
    {
        char *copy = malloc(msglen);
        memcpy(copy, msg, msglen);
        a->write(copy, msglen);
    }
    else
    {
        write(STDOUT_FILENO, msg, msglen);
    }

    return 0;
}

static void load_logic(lua_State *L, char const *filename)
{
    int res = luaL_loadfile(L, filename) || lua_pcall(L, 0, 1, 0);
    if (res == LUA_OK)
    {
        lua_rawsetp(L, LUA_REGISTRYINDEX, &logic_module);
    }
    else
    {
        char const *err = lua_tostring(L, -1);
        printf("Failed to load logic: %s\n", err);
        lua_pop(L, 1);
    }
}

static void start_lua(struct app *a)
{
    if (a->L)
    {
        lua_close(a->L);
    }
    a->L = luaL_newstate();
    luaL_openlibs(a->L);

    lua_pushlightuserdata(a->L, a);
    lua_pushcclosure(a->L, &app_print, 1);
    lua_setglobal(a->L, "print");

    load_logic(a->L, a->logic_filename);
}

struct app *app_new(char const *logic)
{
    struct app *a = malloc(sizeof *a);
    a->logic_filename = logic;
    a->L = NULL;

    start_lua(a);
    return a;
}

void app_reload(struct app *a)
{
    load_logic(a->L, a->logic_filename);
}

void app_free(struct app *a)
{
    if (a)
    {
        lua_close(a->L);
        free(a);
    }
}

static int lua_callback_worker(lua_State *L)
{
    int module_ty = lua_rawgetp(L, LUA_REGISTRYINDEX, &logic_module);
    if (module_ty != LUA_TNIL)
    {
        lua_pushvalue(L, 1);
        lua_gettable(L, -2);
        lua_pushvalue(L, 2);
        lua_call(L, 1, 0);
    }
    return 0;
}

static void lua_callback(lua_State *L, char const *key, char const *arg)
{
    lua_pushcfunction(L, lua_callback_worker);
    lua_pushstring(L, key);
    lua_pushstring(L, arg);

    if (lua_pcall(L, 2, 0, 0))
    {
        char const *err = lua_tostring(L, -1);
        printf("Failed to load logic: %s\n", err);
        lua_pop(L, 1);
    }
}

void do_command(struct app *a, char *line)
{
    if (*line == '/')
    {
        line++;
        if (!strcmp(line, "reload"))
        {
            load_logic(a->L, a->logic_filename);
        }
        else if (!strcmp(line, "restart"))
        {
            start_lua(a);
        }
    }
    else
    {
        lua_callback(a->L, "on_input", line);
    }
}

void do_snote(struct app *a, char *line)
{
    lua_callback(a->L, "on_snote", line);
}

void do_timer(struct app *a)
{
    lua_callback(a->L, "on_timer", NULL);
}

void set_writer(struct app *a, void (*cb)(char*, size_t))
{
    a->write = cb;
}