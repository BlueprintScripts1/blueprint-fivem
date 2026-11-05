from __future__ import annotations

import asyncio
import hmac
import json
import logging
import os

import aiohttp
import discord
from aiohttp import web
from discord.ext import commands

API = "https://discord.com/api/v10"
DEFAULT_PREFIXES = ("bpjobs:", "bpduty:", "bpboss:", "bpstatus:")
METHODS = {"send", "edit", "dm", "followup"}

SETTINGS = {
    "host": os.getenv("BP_BRIDGE_HOST", "0.0.0.0"),
    "port": int(os.getenv("BP_BRIDGE_PORT", "30125")),
    "secret": os.getenv("BP_BRIDGE_SECRET", ""),
    "offline_message": os.getenv("BP_BRIDGE_OFFLINE_MESSAGE", "The FiveM server is offline right now, try again in a moment."),
}

log = logging.getLogger("bp_bridge")


class BPBridge(commands.Cog):
    def __init__(self, bot: commands.Bot):
        self.bot = bot
        self.client_ws: web.WebSocketResponse | None = None
        self.prefixes: set[str] = set(DEFAULT_PREFIXES)
        self.modals: dict[str, dict] = {}
        self.session: aiohttp.ClientSession | None = None
        self.runner: web.AppRunner | None = None

    async def cog_load(self):
        if len(SETTINGS["secret"]) < 16:
            log.error("[bp_bridge] BP_BRIDGE_SECRET is missing or shorter than 16 characters. Bridge not started.")
            return
        self.session = aiohttp.ClientSession()
        app = web.Application(client_max_size=2 * 1024 * 1024)
        app.router.add_get("/", self.handle_ws)
        self.runner = web.AppRunner(app)
        await self.runner.setup()
        await web.TCPSite(self.runner, SETTINGS["host"], SETTINGS["port"]).start()
        log.info("[bp_bridge] Listening on %s:%s", SETTINGS["host"], SETTINGS["port"])

    async def cog_unload(self):
        if self.client_ws is not None:
            await self.client_ws.close()
        if self.runner is not None:
            await self.runner.cleanup()
        if self.session is not None:
            await self.session.close()

    async def rest(self, method: str, path: str, body=None, auth=True, attempt=0):
        headers = {"Content-Type": "application/json", "User-Agent": "DiscordBot (bp_bridge, 1.1)"}
        if auth:
            headers["Authorization"] = "Bot " + self.bot.http.token
        async with self.session.request(method, API + path, json=body, headers=headers) as res:
            if res.status == 429 and attempt < 4:
                data = await res.json(content_type=None)
                await asyncio.sleep(float((data or {}).get("retry_after", 1)) + 0.1)
                return await self.rest(method, path, body, auth, attempt + 1)
            text = await res.text()
            data = json.loads(text) if text else None
            if res.status >= 400:
                raise RuntimeError(f"{method} {path} -> {res.status} {text[:400]}")
            return data

    async def run_call(self, method: str, a: dict):
        if method == "send":
            return (await self.rest("POST", f"/channels/{a['channelId']}/messages", a["payload"]))["id"]
        if method == "edit":
            await self.rest("PATCH", f"/channels/{a['channelId']}/messages/{a['messageId']}", a["payload"])
            return True
        if method == "dm":
            ch = await self.rest("POST", "/users/@me/channels", {"recipient_id": a["userId"]})
            return (await self.rest("POST", f"/channels/{ch['id']}/messages", a["payload"]))["id"]
        if method == "followup":
            await self.rest("POST", f"/webhooks/{self.bot.application_id}/{a['token']}", a["payload"], auth=False)
            return True

    async def answer(self, ws, msg):
        try:
            result = await self.run_call(msg["method"], msg.get("args") or {})
            await ws.send_json({"type": "result", "id": msg["id"], "ok": True, "result": result})
        except Exception as e:
            await ws.send_json({"type": "result", "id": msg["id"], "ok": False, "error": str(e)[:500]})

    async def handle_ws(self, request: web.Request):
        ws = web.WebSocketResponse(heartbeat=30)
        await ws.prepare(request)
        try:
            first = await ws.receive(timeout=10)
            data = json.loads(first.data) if first.type == aiohttp.WSMsgType.TEXT else {}
        except Exception:
            data = {}
        if data.get("type") != "auth" or not hmac.compare_digest(str(data.get("secret", "")), SETTINGS["secret"]):
            log.warning("[bp_bridge] Refused a connection from %s (wrong secret)", request.remote)
            await ws.send_json({"type": "denied", "reason": "wrong secret"})
            await ws.close()
            return ws

        if self.client_ws is not None and not self.client_ws.closed:
            await self.client_ws.close(code=4001, message=b"replaced")
        self.client_ws = ws
        await self.bot.wait_until_ready()
        await ws.send_json({"type": "ready", "bot": str(self.bot.user), "appId": str(self.bot.application_id)})
        log.info("[bp_bridge] FiveM server connected from %s", request.remote)

        async for msg in ws:
            if msg.type != aiohttp.WSMsgType.TEXT:
                continue
            try:
                m = json.loads(msg.data)
            except ValueError:
                continue
            kind = m.get("type")
            if kind == "call" and m.get("method") in METHODS:
                asyncio.create_task(self.answer(ws, m))
            elif kind == "sync":
                self.prefixes = set(DEFAULT_PREFIXES) | {str(p) for p in m.get("prefixes") or []}
                self.modals = {str(k): v for k, v in (m.get("modals") or {}).items()}
            elif kind == "ping":
                await ws.send_json({"type": "pong"})

        if self.client_ws is ws:
            self.client_ws = None
            log.info("[bp_bridge] FiveM server disconnected")
        return ws

    def owned(self, custom_id: str) -> bool:
        return any(custom_id.startswith(p) for p in self.prefixes) or any(custom_id.startswith(p) for p in self.modals)

    @commands.Cog.listener()
    async def on_interaction(self, interaction: discord.Interaction):
        if interaction.type not in (discord.InteractionType.component, discord.InteractionType.modal_submit):
            return
        data = interaction.data or {}
        cid = str(data.get("custom_id", ""))
        if not self.owned(cid):
            return
        callback = f"/interactions/{interaction.id}/{interaction.token}/callback"

        if interaction.type == discord.InteractionType.component:
            modal = next((v for k, v in self.modals.items() if cid.startswith(k)), None)
            if modal is not None:
                await self.rest("POST", callback, {"type": 9, "data": {**modal, "custom_id": cid + ":m"}}, auth=False)
                return

        await self.rest("POST", callback, {"type": 6}, auth=False)

        if self.client_ws is None or self.client_ws.closed:
            await self.rest("POST", f"/webhooks/{self.bot.application_id}/{interaction.token}",
                            {"content": SETTINGS["offline_message"], "flags": 64}, auth=False)
            return

        fields = {}
        for row in data.get("components") or []:
            for c in row.get("components") or ([row["component"]] if row.get("component") else []):
                fields[c.get("custom_id")] = c.get("value")

        user = interaction.user
        payload = {
            "id": str(interaction.id), "token": interaction.token, "appId": str(interaction.application_id),
            "guildId": str(interaction.guild_id or ""), "channelId": str(interaction.channel_id or ""),
            "messageId": str(interaction.message.id) if interaction.message else "",
            "userId": str(user.id), "userName": user.name,
            "roles": [str(r.id) for r in getattr(user, "roles", [])],
            "kind": "button" if interaction.type == discord.InteractionType.component else "modal",
            "customId": cid, "values": data.get("values") or [], "fields": fields,
        }
        await self.client_ws.send_json({"type": "interaction", "data": payload})


async def setup(bot: commands.Bot):
    await bot.add_cog(BPBridge(bot))
