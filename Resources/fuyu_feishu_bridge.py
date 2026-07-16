#!/usr/bin/env python3
"""Small JSON-lines bridge between FuYu and Feishu's official Python SDK."""

import json
import os
import sys
import threading
import uuid

import lark_oapi as lark
from lark_oapi.api.im.v1 import (
    CreateMessageRequest,
    CreateMessageRequestBody,
)
from lark_oapi.event.dispatcher_handler import EventDispatcherHandler
from lark_oapi.ws import Client as FeishuWSClient


APP_ID = os.environ.get("FUYU_FEISHU_APP_ID", "").strip()
APP_SECRET = os.environ.get("FUYU_FEISHU_APP_SECRET", "").strip()
PREFIX = "FUYU_EVENT "

if not APP_ID or not APP_SECRET:
    print(PREFIX + json.dumps({"kind": "status", "status": "error", "message": "missing credentials"}), flush=True)
    raise SystemExit(2)


client = (
    lark.Client.builder()
    .app_id(APP_ID)
    .app_secret(APP_SECRET)
    .log_level(lark.LogLevel.ERROR)
    .build()
)


def emit(payload):
    print(PREFIX + json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def on_message(data):
    event = getattr(data, "event", None)
    message = getattr(event, "message", None)
    sender = getattr(event, "sender", None)
    if not message or not sender or getattr(message, "message_type", "") != "text":
        return
    try:
        content = json.loads(getattr(message, "content", "{}") or "{}")
        text = str(content.get("text", "")).strip()
    except Exception:
        return
    if not text:
        return
    sender_id = getattr(getattr(sender, "sender_id", None), "open_id", "") or ""
    emit({
        "kind": "message",
        "message_id": getattr(message, "message_id", "") or "",
        "chat_id": getattr(message, "chat_id", "") or "",
        "sender_id": sender_id,
        "text": text,
    })


def send_text(chat_id, text):
    body = (
        CreateMessageRequestBody.builder()
        .receive_id(chat_id)
        .msg_type("text")
        .content(json.dumps({"text": text}, ensure_ascii=False))
        .uuid(str(uuid.uuid4()))
        .build()
    )
    request = (
        CreateMessageRequest.builder()
        .receive_id_type("chat_id")
        .request_body(body)
        .build()
    )
    response = client.im.v1.message.create(request)
    if not response.success():
        emit({"kind": "status", "status": "send_error", "message": f"{response.code}: {response.msg}"})


def stdin_loop():
    for raw in sys.stdin:
        try:
            command = json.loads(raw)
            if command.get("kind") == "reply":
                send_text(str(command.get("chat_id", "")), str(command.get("text", "")))
        except Exception as exc:
            emit({"kind": "status", "status": "command_error", "message": str(exc)})


handler = (
    EventDispatcherHandler.builder("", "")
    .register_p2_im_message_receive_v1(on_message)
    .build()
)

threading.Thread(target=stdin_loop, name="fuyu-feishu-replies", daemon=True).start()
emit({"kind": "status", "status": "connecting"})
FeishuWSClient(
    app_id=APP_ID,
    app_secret=APP_SECRET,
    log_level=lark.LogLevel.ERROR,
    event_handler=handler,
    extra_ua_tags=["channel"],
).start()
