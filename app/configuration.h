#ifndef CONFIGURATION_H
#define CONFIGURATION_H

struct configuration
{
    char const* console_node;
    char const* console_service;
    char const* lua_filename;
    char const* irc_node;
    char const* irc_service;
    char const* irc_nick;
    char const* irc_pass;
};

struct configuration load_configuration(int argc, char **argv);

#endif