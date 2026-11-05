BPConfig = {
    // 'builtin' = bp_discord runs its own bot inside the FiveM server.
    //             Put the token in server.cfg:  set bp_discord_token "YOUR_BOT_TOKEN"
    // 'custom'  = use YOUR OWN bot (discord.py or discord.js). Add the bridge from the bot-bridge folder to your bot
    //             (see bot-bridge/README.md), then fill in "custom" below.
    mode: 'builtin',

    // Builtin mode only: the bot's status text ("Watching over the city")
    activity: 'over the city',

    custom: {
        // Where your bot's bridge is listening.
        //   Bot on the same machine as FiveM:    ws://127.0.0.1:30125
        //   Bot hosting with port forwarding:    ws://YOUR_BOT_HOST_IP:FORWARDED_PORT
        url: 'ws://127.0.0.1:30125',

        // The shared secret is NOT set here. Put it in server.cfg (same value as BP_BRIDGE_SECRET on your bot):
        //   set bp_discord_secret "a-long-random-secret"
    },
};
