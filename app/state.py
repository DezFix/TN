import io
import json
import os
import re
import time
import uuid

import flet as ft

STORAGE_KEY = 'tn-notes-data-v1'
MEDIA_DIR = 'tn_media'

COLORS = ['#2AABEE', '#E0663E', '#7C5CD6', '#3EA66E', '#D6538B', '#C99A2E', '#5C7CFA', '#20B2AA']
ICONS = [None, '💡', '📌', '💼', '🎯', '📚', '🎨', '🎧', '🍳', '✈️', '🌱', '⚡', '🧠', '❤️', '🏋️', '🎵']

DEFAULT_CHATS = []


class MediaStore:
    def __init__(self):
        self.dir = None

    async def init(self):
        try:
            docs = await ft.StoragePaths().get_application_documents_directory()
        except Exception:
            docs = os.path.expanduser('~')
        self.dir = os.path.join(docs, MEDIA_DIR)
        os.makedirs(self.dir, exist_ok=True)

    def save_bytes(self, filename, data):
        path = os.path.join(self.dir, filename)
        with open(path, 'wb') as f:
            f.write(data)
        return path

    def path(self, filename):
        return os.path.join(self.dir, filename)

    def remove(self, filename):
        try:
            os.remove(os.path.join(self.dir, filename))
        except OSError:
            pass


class State:
    def __init__(self):
        self.theme = 'light'
        self.chats = list(DEFAULT_CHATS)
        self.entries = []

    async def load(self):
        try:
            raw = await ft.SharedPreferences().get(STORAGE_KEY)
            if raw:
                data = json.loads(raw)
                if isinstance(data.get('chats'), list) and data['chats']:
                    self.chats = data['chats']
                if isinstance(data.get('entries'), list):
                    self.entries = data['entries']
                if data.get('theme') in ('light', 'dark'):
                    self.theme = data['theme']
        except Exception:
            pass

    async def save(self):
        try:
            await ft.SharedPreferences().set(STORAGE_KEY, json.dumps({
                'theme': self.theme,
                'chats': self.chats,
                'entries': self.entries,
            }, ensure_ascii=False))
        except Exception:
            pass

    def chat_by_id(self, chat_id):
        for c in self.chats:
            if c['id'] == chat_id:
                return c
        return None

    def entries_for(self, chat_id):
        return sorted((e for e in self.entries if e['chatId'] == chat_id), key=lambda e: e['ts'])


def uid(prefix):
    return '{}_{:x}_{}'.format(prefix, int(time.time() * 1000), uuid.uuid4().hex[:6])


def extract_tags(text):
    matches = re.findall(r'#[\wа-яА-ЯёЁ]+', text) or []
    return list(dict.fromkeys(m[1:].lower() for m in matches))


def compress_image(data, max_w=1280, quality=72):
    try:
        from PIL import Image
        img = Image.open(io.BytesIO(data))
        img = img.convert('RGB')
        if img.width > max_w:
            h = round(img.height * max_w / img.width)
            img = img.resize((max_w, h))
        buf = io.BytesIO()
        img.save(buf, 'JPEG', quality=quality)
        return buf.getvalue()
    except Exception:
        return data