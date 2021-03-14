#include <string.h>

#include "ircmsg.h"

static char *word(char **msg)
{
    if (NULL == *msg || '\0' == **msg) return NULL;
    char *start = strsep(msg, " ");
    if (NULL != *msg)
    {
        while (' ' == **msg) (*msg)++;
    }
    return start;
}

static void unescape_tag_value(char *val)
{
    char *write = val;
    for (char *cursor = val; *cursor; cursor++)
    {
        if (*cursor == '\\')
        {
            cursor++;
            switch (*cursor)
            {
                case ':' : *write++ = ';'    ; break;
                case 's' : *write++ = ' '    ; break;
                case 'r' : *write++ = '\r'   ; break;
                case 'n' : *write++ = '\n'   ; break;
                case '\0': *write   = '\0'   ; return;
                default  : *write++ = *cursor; break;
            }
        }
        else
        {
            *write++ = *cursor;
        }
    }
    *write = '\0';
}

static inline int parse_tags(struct ircmsg *out, char *tagpart)
{
    char const* const delim = ";";
    char *last;
    int i = 0;
    for (char *keyval = strtok_r(tagpart, delim, &last);
        keyval;
        keyval = strtok_r(NULL, delim, &last))
    {
        if (i >= MAX_MSG_TAGS) return 1;
        char *key = strsep(&keyval, "=");
        if (NULL != keyval) unescape_tag_value(keyval);

        out->tags[i] = (struct tag) {
            .key = key,
            .val = keyval,
        };

        i++;
    }
    out->tags_n = i;
    return 0;
}

int parse_irc_message(struct ircmsg *out, char *msg)
{
    /* MESSAGE TAGS */
    if (*msg == '@') 
    {
        msg++;
        char *tagpart = word(&msg);
        if (NULL == tagpart) return 1;
        if (parse_tags(out, tagpart)) return 2;
    }
    else
    {
        out->tags_n = 0;
    }

    /* MESSAGE SOURCE */
    if (*msg == ':')
    {
        msg++;
        char *source = word(&msg);
        if (NULL == source) return 3;
        out->source = source;
    }
    else
    {
        out->source = NULL;
    }

    /* MESSAGE COMMANDS */
    char *command = word(&msg);
    if (NULL == command) return 4;
    out->command = command;

    /* MESSAGE ARGUMENTS */
    if (msg == NULL) {
        out->args_n = 0;
        return 0;
    }

    for (int i = 0;; i++) 
    {
        if (*msg == ':')
        {
            out->args[i] = msg+1;
            out->args_n = i+1;
            return 0;
        }

        if (i+1 == MAX_ARGS)
        {
            out->args[i] = msg;
            out->args_n = i+1;
            return 0;
        }

        char *arg = word(&msg);
        out->args[i] = arg;

        if (NULL == msg)
        {
            out->args_n = i+1;
            return 0;
        }
    }

    return 0;
}
