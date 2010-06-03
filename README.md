KarmaBot
========

KarmaBot is a little ruby-written irc bot that take note of user's karmas.

--------------------

How to use it?
--------------

To decrease karma for 'user' you must send a message to the channel where the
bot is working like 'user++', to decrease 'user--', to see "user"'s karma just
send '-karma user'.
You can vote only online users.

Nothing special, but working well :D

How to configure?
-----------------

You have two modes to configure KarmaBot, by enviroment variabile or arguments

ENVIROMENT VARIABILE are:
    - KB_DB         # Database path
    - KB_OWNER      # Owner's name
    - KB_NICK       # Bot's nickname
    - KB_USER       # Bot's username
    - KB_REAL       # Bot's realname
    - KB_SERVER     # Server address
    - KB_PORT       # Server port
    - KB_CHAN       # IRC Channel
    - KB_SSL        # Use ssl? [yes|no]

ARGUMENTS are:
    - d             # Database path
    - o             # Owner's name
    - n             # Bot's nickname
    - u             # Bot's username
    - r             # Bot's realname
    - s             # Server address
    - p             # Server port
    - c             # IRC Channel
    - S             # Use ssl? [yes|no]

    - U             # Update bot :D
