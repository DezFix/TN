import random
import time

import flet as ft

from app.state import COLORS, ICONS, MediaStore, State, compress_image, extract_tags, uid
from app.theme import palette_for
from app.widgets import (
    avatar,
    build_chat_row,
    build_forward_row,
    day_pill,
    fmt_day,
    fmt_time,
    hashtag_text,
)


class NotesApp:
    def __init__(self, page):
        self.page = page
        self.state = State()
        self.media = MediaStore()
        self.p = palette_for(self.state.theme)
        self.current_chat_id = None
        self.editing_entry_id = None
        self.search_q = ''
        self.selected_color = COLORS[0]
        self.selected_icon = ICONS[0]
        self.editing_chat_id = None

        self.screen_list = None
        self.screen_chat = None
        self.screen_settings = None
        self.list_topbar = None
        self.chat_topbar = None
        self.settings_topbar = None
        self.composer = None
        self.chat_list_view = None
        self.messages_view = None
        self.search_field = None
        self.text_input = None
        self.send_btn = None
        self.fab = None

    async def init(self):
        await self.media.init()
        await self.state.load()
        self.build_ui()
        self.apply_theme()
        self.screen_chat.visible = False
        self.screen_settings.visible = False
        self.page.update()

    # ---------------- UI BUILD ----------------

    def build_ui(self):
        self.screen_list = ft.Container(expand=True, bgcolor=self.p.bg_list)
        self.screen_chat = ft.Container(expand=True, bgcolor=self.p.bg_chat)
        self.screen_settings = ft.Container(expand=True, bgcolor=self.p.bg)

        self.list_topbar = ft.Container()
        self.chat_topbar = ft.Container()
        self.settings_topbar = ft.Container()
        self.composer = ft.Container()

        self.chat_list_view = ft.ListView(expand=True, spacing=0, padding=0)
        self.messages_view = ft.ListView(
            expand=True,
            spacing=6,
            padding=ft.Padding.only(top=14, left=12, right=12, bottom=10),
            auto_scroll=True,
        )

        self.screen_list.content = ft.Column(expand=True, spacing=0, controls=[self.list_topbar, self.chat_list_view])
        self.screen_chat.content = ft.Column(expand=True, spacing=0, controls=[self.chat_topbar, self.messages_view, self.composer])

        self.fab = ft.FloatingActionButton(
            icon=ft.Icons.EDIT,
            bgcolor=self.p.accent,
            on_click=lambda e: self.open_chat_modal(None),
        )
        self.page.floating_action_button = self.fab

        self.screen_settings.content = ft.Column(expand=True, spacing=0, controls=[self.settings_topbar])

        self.page.add(ft.Column(expand=True, spacing=0, controls=[self.screen_list, self.screen_chat, self.screen_settings]))

    def apply_theme(self):
        self.p = palette_for(self.state.theme)
        self.page.theme_mode = ft.ThemeMode.DARK if self.state.theme == 'dark' else ft.ThemeMode.LIGHT
        self.page.bgcolor = self.p.bg
        self.page.theme = ft.Theme(color_scheme_seed=self.p.accent, use_material3=True)

        self.screen_list.bgcolor = self.p.bg_list
        self.screen_chat.bgcolor = self.p.bg_chat
        self.screen_settings.bgcolor = self.p.bg
        self.fab.bgcolor = self.p.accent

        old_search = self.search_field.value if self.search_field else ''
        old_text = self.text_input.value if self.text_input else ''

        self.list_topbar.bgcolor = self.p.bg
        self.list_topbar.border = ft.Border.only(bottom=ft.BorderSide(1, self.p.divider))
        self.list_topbar.padding = ft.Padding.only(left=12, right=12, top=14, bottom=10)
        self.list_topbar.content = self.build_list_topbar(old_search)

        self.chat_topbar.bgcolor = self.p.bg
        self.chat_topbar.border = ft.Border.only(bottom=ft.BorderSide(1, self.p.divider))
        self.chat_topbar.padding = ft.Padding.symmetric(horizontal=14, vertical=10)
        self.chat_topbar.content = self.build_chat_topbar()

        self.composer.bgcolor = self.p.bg
        self.composer.border = ft.Border.only(top=ft.BorderSide(1, self.p.divider))
        self.composer.padding = ft.Padding.only(left=10, right=10, top=8, bottom=10)
        self.composer.content = self.build_composer()
        if old_text:
            self.text_input.value = old_text
        self.send_btn.icon = ft.Icons.SEND if (self.text_input.value or '').strip() else ft.Icons.MIC

        self.settings_topbar.bgcolor = self.p.bg
        self.settings_topbar.border = ft.Border.only(bottom=ft.BorderSide(1, self.p.divider))
        self.settings_topbar.padding = ft.Padding.symmetric(horizontal=14, vertical=10)
        self.settings_topbar.content = self.build_settings_topbar()

        self.screen_settings.content = ft.Column(expand=True, spacing=0, controls=[self.settings_topbar, self.build_settings_body()])

        self.render_chat_list()
        if self.current_chat_id:
            self.render_messages()
        self.page.update()

    def build_list_topbar(self, value=''):
        self.search_field = ft.TextField(
            value=value,
            hint_text='Поиск по чатам и записям',
            prefix_icon=ft.Icons.SEARCH,
            filled=True,
            fill_color=self.p.bg_chat,
            border=ft.InputBorder.NONE,
            border_radius=10,
            dense=True,
            text_size=14.5,
            content_padding=ft.Padding.symmetric(horizontal=12, vertical=9),
            on_change=self.on_search_change,
        )
        return ft.Column(
            spacing=10,
            controls=[
                ft.Row(
                    controls=[
                        ft.Container(width=34),
                        ft.Text('Заметки', size=19, weight=ft.FontWeight.W_700, color=self.p.text, expand=True, text_align=ft.TextAlign.CENTER),
                        ft.IconButton(icon=ft.Icons.SETTINGS, icon_color=self.p.text_soft, on_click=lambda e: self.show_screen('settings')),
                    ],
                ),
                self.search_field,
            ],
        )

    def build_chat_topbar(self):
        chat = self.state.chat_by_id(self.current_chat_id) if self.current_chat_id else None
        return ft.Row(
            spacing=10,
            controls=[
                ft.IconButton(icon=ft.Icons.ARROW_BACK, icon_color=self.p.accent, on_click=lambda e: self.close_chat()),
                ft.GestureDetector(
                    on_tap=lambda e: self.open_chat_modal(self.current_chat_id),
                    content=avatar(chat, size=36, p=self.p) if chat else ft.Container(width=36, height=36),
                ),
                ft.Column(
                    expand=True,
                    spacing=0,
                    controls=[
                        ft.Text(chat['name'] if chat else '', size=16, weight=ft.FontWeight.W_600, color=self.p.text, overflow=ft.TextOverflow.ELLIPSIS, max_lines=1),
                        ft.Text('заметки самому себе', size=12, color=self.p.text_faint),
                    ],
                ),
                ft.IconButton(icon=ft.Icons.EDIT, icon_color=self.p.text_faint, on_click=lambda e: self.open_chat_modal(self.current_chat_id)),
                ft.IconButton(icon=ft.Icons.DELETE, icon_color=self.p.text_faint, on_click=lambda e: self.confirm_delete_chat()),
            ],
        )

    def build_settings_topbar(self):
        return ft.Row(
            spacing=10,
            controls=[
                ft.IconButton(icon=ft.Icons.ARROW_BACK, icon_color=self.p.accent, on_click=lambda e: self.show_screen('list')),
                ft.Text('Настройки', size=16, weight=ft.FontWeight.W_600, color=self.p.text),
            ],
        )

    def build_settings_body(self):
        return ft.Column(
            expand=True,
            controls=[
                ft.Container(
                    padding=ft.Padding.only(left=16, right=16, top=18, bottom=4),
                    content=ft.Column(
                        spacing=8,
                        controls=[
                            ft.Text('ОФОРМЛЕНИЕ', size=12, weight=ft.FontWeight.W_600, color=self.p.text_faint),
                            ft.Container(
                                bgcolor=self.p.bg_chat,
                                border_radius=12,
                                content=ft.Column(
                                    spacing=0,
                                    controls=[
                                        ft.Container(
                                            padding=ft.Padding.symmetric(horizontal=14, vertical=13),
                                            content=ft.Row(
                                                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                                                controls=[
                                                    ft.Text('Тема', size=14.5, color=self.p.text),
                                                    self.build_theme_toggle(),
                                                ],
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                            ft.Text(
                                'Иконку, цвет и название каждого чата можно менять — откройте чат и нажмите ✎ рядом с его названием.',
                                size=12,
                                color=self.p.text_faint,
                            ),
                        ],
                    ),
                ),
            ],
        )

    def build_theme_toggle(self):
        def opt(label, theme):
            active = self.state.theme == theme
            return ft.GestureDetector(
                on_tap=lambda e: self.set_theme(theme),
                content=ft.Container(
                    padding=ft.Padding.symmetric(horizontal=14, vertical=6),
                    border_radius=7,
                    bgcolor=self.p.accent if active else ft.Colors.TRANSPARENT,
                    content=ft.Text(
                        label,
                        size=13,
                        weight=ft.FontWeight.W_600,
                        color=ft.Colors.WHITE if active else self.p.text_soft,
                    ),
                ),
            )

        return ft.Container(
            bgcolor=self.p.bg,
            border_radius=9,
            padding=3,
            content=ft.Row(spacing=2, controls=[opt('Светлая', 'light'), opt('Тёмная', 'dark')]),
        )

    def build_composer(self):
        self.text_input = ft.TextField(
            hint_text='Сообщение…',
            multiline=True,
            min_lines=1,
            max_lines=4,
            shift_enter=True,
            filled=True,
            fill_color=self.p.bg_chat,
            border=ft.InputBorder.NONE,
            border_radius=18,
            text_size=14.5,
            content_padding=ft.Padding.symmetric(horizontal=14, vertical=9),
            expand=True,
            on_change=lambda e: self.update_send_btn(),
            on_submit=lambda e: self.send_text(),
        )
        self.send_btn = ft.IconButton(icon=ft.Icons.MIC, icon_color=ft.Colors.WHITE, bgcolor=self.p.accent, on_click=lambda e: self.on_send_click())
        return ft.Row(
            spacing=6,
            controls=[
                ft.IconButton(icon=ft.Icons.ATTACH_FILE, icon_color=self.p.text_soft, on_click=lambda e: self.pick_image()),
                ft.IconButton(icon=ft.Icons.VIDEOCAM, icon_color=self.p.text_soft, on_click=lambda e: self.pick_video()),
                self.text_input,
                self.send_btn,
            ],
        )

    # ---------------- NAVIGATION ----------------

    def show_screen(self, name):
        self.screen_list.visible = name == 'list'
        self.screen_chat.visible = name == 'chat'
        self.screen_settings.visible = name == 'settings'
        self.fab.visible = name == 'list'
        self.page.update()

    def open_chat(self, chat_id):
        self.current_chat_id = chat_id
        self.editing_entry_id = None
        self.chat_topbar.content = self.build_chat_topbar()
        self.chat_topbar.update()
        self.render_messages()
        self.show_screen('chat')

    def close_chat(self):
        self.current_chat_id = None
        self.editing_entry_id = None
        self.render_chat_list()
        self.show_screen('list')

    # ---------------- CHAT LIST ----------------

    def on_search_change(self, e):
        self.search_q = e.control.value.strip()
        self.render_chat_list()

    def render_chat_list(self):
        q = self.search_q.lower()
        chats = []
        for c in self.state.chats:
            if not q:
                chats.append(c)
                continue
            if q in c['name'].lower():
                chats.append(c)
                continue
            for e in self.state.entries_for(c['id']):
                if q in (e.get('text', '') or '').lower() or any(q in t for t in e.get('tags', [])):
                    chats.append(c)
                    break

        def last_ts(c):
            entries = self.state.entries_for(c['id'])
            return entries[-1]['ts'] if entries else 0

        chats.sort(key=last_ts, reverse=True)

        rows = []
        for c in chats:
            rows.append(build_chat_row(c, self.state, self.p, self.open_chat))

        if not rows:
            rows = [
                ft.Container(
                    padding=ft.Padding.symmetric(horizontal=30, vertical=60),
                    content=ft.Text('Ничего не найдено', size=14, color=self.p.text_faint, text_align=ft.TextAlign.CENTER),
                )
            ]
        self.chat_list_view.controls = rows
        self.chat_list_view.update()

    # ---------------- MESSAGES ----------------

    def render_messages(self):
        if not self.current_chat_id:
            return
        items = []
        last_day = None
        for entry in self.state.entries_for(self.current_chat_id):
            day = fmt_day(entry['ts'])
            if day != last_day:
                items.append(day_pill(day, self.p))
                last_day = day
            items.append(self.build_bubble(entry))
        if not items:
            items = [
                ft.Container(
                    padding=ft.Padding.symmetric(horizontal=40, vertical=60),
                    content=ft.Text(
                        'Пока пусто. Напишите текст, прикрепите фото или запишите голосовую заметку — она появится здесь.',
                        size=13.5,
                        color=self.p.text_faint,
                        text_align=ft.TextAlign.CENTER,
                    ),
                )
            ]
        self.messages_view.controls = items
        self.messages_view.update()

    def build_bubble(self, entry):
        p = self.p
        bubble = None
        if entry['type'] == 'text':
            if self.editing_entry_id == entry['id']:
                bubble = self.build_edit_box(entry)
            else:
                bubble = ft.Container(
                    bgcolor=p.bubble_own,
                    border=ft.Border.all(1, p.bubble_border),
                    border_radius=ft.BorderRadius(14, 14, 14, 3),
                    padding=ft.Padding.only(left=10, top=7, right=9, bottom=6),
                    content=ft.Column(
                        spacing=1,
                        controls=[
                            hashtag_text(entry['text'], p),
                            ft.Row(
                                alignment=ft.MainAxisAlignment.END,
                                controls=[ft.Text(fmt_time(entry['ts']), size=10.5, color=p.text_faint)],
                            ),
                        ],
                    ),
                )
        elif entry['type'] == 'image':
            bubble = ft.Container(
                border_radius=10,
                clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                content=ft.Column(
                    spacing=2,
                    controls=[
                        ft.Image(src=self.media.path(entry['media']), width=300, fit=ft.BoxFit.COVER, border_radius=10),
                        ft.Row(
                            alignment=ft.MainAxisAlignment.END,
                            controls=[ft.Text(fmt_time(entry['ts']), size=10.5, color=p.text_faint)],
                        ),
                    ],
                ),
            )
        elif entry['type'] == 'audio':
            bubble = ft.Container(
                bgcolor=p.bubble_own,
                border=ft.Border.all(1, p.bubble_border),
                border_radius=ft.BorderRadius(14, 14, 14, 3),
                padding=ft.Padding.symmetric(horizontal=12, vertical=8),
                content=ft.Row(
                    spacing=9,
                    controls=[
                        ft.Container(
                            width=32, height=32, border_radius=16, bgcolor=p.accent,
                            alignment=ft.Alignment.CENTER,
                            content=ft.Icon(ft.Icons.PLAY_ARROW, size=16, color=ft.Colors.WHITE),
                        ),
                        ft.Column(
                            spacing=1,
                            controls=[
                                ft.Text('Голосовое сообщение', size=13, weight=ft.FontWeight.W_500, color=p.text),
                                ft.Text('{} сек · {}'.format(entry.get('duration', 0), fmt_time(entry['ts'])), size=11, color=p.text_faint),
                            ],
                        ),
                    ],
                ),
            )
        elif entry['type'] == 'video':
            bubble = ft.Container(
                bgcolor=p.bubble_own,
                border=ft.Border.all(1, p.bubble_border),
                border_radius=ft.BorderRadius(14, 14, 14, 3),
                padding=ft.Padding.symmetric(horizontal=12, vertical=8),
                content=ft.Row(
                    spacing=9,
                    controls=[
                        ft.Container(
                            width=32, height=32, border_radius=16, bgcolor=p.accent,
                            alignment=ft.Alignment.CENTER,
                            content=ft.Icon(ft.Icons.PLAY_ARROW, size=16, color=ft.Colors.WHITE),
                        ),
                        ft.Column(
                            expand=True,
                            spacing=1,
                            controls=[
                                ft.Text(entry.get('mediaName', 'Видео'), size=13, weight=ft.FontWeight.W_500, color=p.text, overflow=ft.TextOverflow.ELLIPSIS, max_lines=1),
                                ft.Text('{} · {}'.format(entry.get('mediaSize', ''), fmt_time(entry['ts'])), size=11, color=p.text_faint),
                            ],
                        ),
                    ],
                ),
            )
        return ft.Column(
            horizontal_alignment=ft.CrossAxisAlignment.END,
            controls=[
                ft.GestureDetector(
                    on_long_press=lambda e, en=entry: self.open_ctx_menu(en),
                    on_secondary_tap=lambda e, en=entry: self.open_ctx_menu(en),
                    content=bubble,
                )
            ],
        )

    def build_edit_box(self, entry):
        p = self.p
        field = ft.TextField(
            value=entry['text'],
            multiline=True,
            min_lines=2,
            max_lines=6,
            text_size=14.5,
            border=ft.Border.all(1, p.accent),
            border_radius=8,
            filled=True,
            fill_color=p.bg,
        )

        async def save(e):
            text = field.value.strip()
            if not text:
                return
            entry['text'] = text
            entry['tags'] = extract_tags(text)
            self.editing_entry_id = None
            await self.state.save()
            self.render_messages()
            self.render_chat_list()

        def cancel(e):
            self.editing_entry_id = None
            self.render_messages()

        return ft.Container(
            bgcolor=p.bubble_own,
            border=ft.Border.all(1, p.bubble_border),
            border_radius=ft.BorderRadius(14, 14, 14, 3),
            padding=8,
            width=320,
            content=ft.Column(
                spacing=6,
                controls=[
                    field,
                    ft.Row(
                        alignment=ft.MainAxisAlignment.END,
                        spacing=6,
                        controls=[
                            ft.TextButton('Отмена', style=ft.ButtonStyle(color=p.text_soft), on_click=cancel),
                            ft.FilledButton('Сохранить', bgcolor=p.accent, on_click=save),
                        ],
                    ),
                ],
            ),
        )

    # ---------------- COMPOSER ----------------

    def update_send_btn(self):
        has = bool(self.text_input and self.text_input.value.strip())
        self.send_btn.icon = ft.Icons.SEND if has else ft.Icons.MIC
        self.send_btn.update()

    def on_send_click(self):
        if self.text_input.value.strip():
            self.send_text()
        else:
            self.toast('Голосовые заметки — скоро появятся', error=True)

    async def send_text(self):
        text = self.text_input.value.strip()
        if not text or not self.current_chat_id:
            return
        self.state.entries.append({
            'id': uid('e'),
            'chatId': self.current_chat_id,
            'type': 'text',
            'text': text,
            'tags': extract_tags(text),
            'ts': int(time.time() * 1000),
        })
        self.text_input.value = ''
        self.update_send_btn()
        await self.state.save()
        self.render_messages()
        self.render_chat_list()

    async def pick_image(self):
        if not self.current_chat_id:
            return
        try:
            files = await ft.FilePicker().pick_files(file_type=ft.FilePickerFileType.IMAGE, with_data=True)
            if not files:
                return
            f = files[0]
            data = f.bytes if f.bytes else open(f.path, 'rb').read()
            await self.add_media('image', data)
        except Exception:
            self.toast('Не получилось прикрепить фото', error=True)

    async def pick_video(self):
        if not self.current_chat_id:
            return
        try:
            files = await ft.FilePicker().pick_files(file_type=ft.FilePickerFileType.VIDEO, with_data=True)
            if not files:
                return
            f = files[0]
            data = f.bytes if f.bytes else open(f.path, 'rb').read()
            await self.add_media('video', data, name=f.name, size_label='{:.1f} МБ'.format(f.size / 1024 / 1024))
        except Exception:
            self.toast('Не получилось прикрепить видео', error=True)

    async def add_media(self, mtype, data, name='', size_label=''):
        if not self.current_chat_id:
            return
        eid = uid('e')
        ext = '.jpg' if mtype == 'image' else '.vid'
        fn = eid + ext
        if mtype == 'image':
            data = compress_image(data)
        self.media.save_bytes(fn, data)
        self.state.entries.append({
            'id': eid,
            'chatId': self.current_chat_id,
            'type': mtype,
            'text': '',
            'tags': [],
            'ts': int(time.time() * 1000),
            'media': fn,
            'duration': 0,
            'mediaName': name,
            'mediaSize': size_label,
        })
        await self.state.save()
        self.render_messages()
        self.render_chat_list()

    # ---------------- CONTEXT MENU ----------------

    def open_ctx_menu(self, entry):
        p = self.p
        tiles = []

        if entry['type'] == 'text':
            def copy_action(e):
                self.page.pop_dialog(sheet)
                self.page.run_task(self.do_copy, entry['text'])

            def edit_action(e):
                self.page.pop_dialog(sheet)
                self.editing_entry_id = entry['id']
                self.render_messages()

            tiles.append(ft.ListTile(leading=ft.Icon(ft.Icons.COPY), title=ft.Text('Копировать'), on_click=copy_action))
            tiles.append(ft.ListTile(leading=ft.Icon(ft.Icons.EDIT), title=ft.Text('Изменить'), on_click=edit_action))

        def forward_action(e):
            self.page.pop_dialog(sheet)
            self.open_forward(entry)

        def delete_action(e):
            self.page.pop_dialog(sheet)
            self.confirm_delete_entry(entry)

        tiles.append(ft.ListTile(leading=ft.Icon(ft.Icons.FORWARD), title=ft.Text('Переслать'), on_click=forward_action))
        tiles.append(ft.ListTile(
            leading=ft.Icon(ft.Icons.DELETE, color=p.danger),
            title=ft.Text('Удалить', color=p.danger),
            on_click=delete_action,
        ))

        sheet = ft.BottomSheet(
            content=ft.Column(tiles, tight=True),
            bgcolor=p.modal_bg,
            show_drag_handle=True,
        )
        self.page.show_dialog(sheet)

    async def do_copy(self, text):
        try:
            await self.page.clipboard.set(text)
            self.toast('Скопировано')
        except Exception:
            pass

    def open_forward(self, entry):
        p = self.p

        def pick(chat):
            self.page.pop_dialog(dlg)
            self.page.run_task(self.do_forward, entry, chat)

        rows = [build_forward_row(c, p, lambda ch=c: pick(ch)) for c in self.state.chats]
        dlg = ft.AlertDialog(
            title=ft.Text('Переслать в…', size=16, weight=ft.FontWeight.W_700, color=p.text),
            content=ft.ListView(rows, height=300, spacing=2),
            actions=[ft.TextButton('Отмена', style=ft.ButtonStyle(color=p.text_soft), on_click=lambda e: self.page.pop_dialog(dlg))],
            bgcolor=p.modal_bg,
        )
        self.page.show_dialog(dlg)

    async def do_forward(self, entry, chat):
        copy = dict(entry)
        copy['id'] = uid('e')
        copy['ts'] = int(time.time() * 1000)
        copy['chatId'] = chat['id']
        self.state.entries.append(copy)
        await self.state.save()
        if chat['id'] == self.current_chat_id:
            self.render_messages()
        self.render_chat_list()
        self.toast('Переслано в «{}»'.format(chat['name']))

    def confirm_delete_entry(self, entry):
        p = self.p
        dlg = ft.AlertDialog(
            title=ft.Text('Удалить запись?', size=16, weight=ft.FontWeight.W_700, color=p.text),
            bgcolor=p.modal_bg,
            actions=[
                ft.TextButton('Отмена', style=ft.ButtonStyle(color=p.text_soft), on_click=lambda e: self.page.pop_dialog(dlg)),
                ft.TextButton(
                    'Удалить',
                    style=ft.ButtonStyle(color=p.danger),
                    on_click=lambda e: self.delete_entry(entry, dlg),
                ),
            ],
        )
        self.page.show_dialog(dlg)

    async def delete_entry(self, entry, dlg):
        self.page.pop_dialog(dlg)
        self.media.remove(entry.get('media', ''))
        self.state.entries = [e for e in self.state.entries if e['id'] != entry['id']]
        await self.state.save()
        self.render_messages()
        self.render_chat_list()

    # ---------------- CHAT MODAL ----------------

    def open_chat_modal(self, chat_id=None):
        p = self.p
        self.editing_chat_id = chat_id
        chat = self.state.chat_by_id(chat_id) if chat_id else None
        name_field = ft.TextField(
            value=chat['name'] if chat else '',
            hint_text='Название, например «Идеи»',
            text_size=14,
            border_radius=8,
            filled=True,
            fill_color=p.bg,
        )
        if chat:
            self.selected_color = chat['color']
            self.selected_icon = chat['icon']
        else:
            self.selected_color = COLORS[random.randrange(len(COLORS))]
            self.selected_icon = None

        icon_row = ft.Row(wrap=True, spacing=8, run_spacing=8, controls=[])
        color_row = ft.Row(wrap=True, spacing=9, run_spacing=9, controls=[])
        self.build_icon_picker(icon_row, initial=True)
        self.build_color_picker(color_row, initial=True)

        dlg = ft.AlertDialog(
            modal=True,
            title=ft.Text('Изменить чат' if chat else 'Новый чат заметок', size=16, weight=ft.FontWeight.W_700, color=p.text),
            content=ft.Column(
                tight=True,
                spacing=12,
                width=340,
                controls=[
                    name_field,
                    ft.Text('ИКОНКА', size=11.5, weight=ft.FontWeight.W_600, color=p.text_faint),
                    icon_row,
                    ft.Text('ЦВЕТ', size=11.5, weight=ft.FontWeight.W_600, color=p.text_faint),
                    color_row,
                ],
            ),
            actions=[
                ft.TextButton('Отмена', style=ft.ButtonStyle(color=p.text_soft), on_click=lambda e: self.page.pop_dialog(dlg)),
                ft.FilledButton('Сохранить' if chat else 'Создать', bgcolor=p.accent, on_click=lambda e: self.save_chat_modal(name_field, dlg)),
            ],
            bgcolor=p.modal_bg,
        )
        self.page.show_dialog(dlg)

    def build_icon_picker(self, icon_row, initial=False):
        p = self.p
        cells = []
        for ic in ICONS:
            sel = ic == self.selected_icon
            cells.append(ft.GestureDetector(
                on_tap=lambda e, i=ic: self.pick_icon(i, icon_row),
                content=ft.Container(
                    width=36, height=36, border_radius=9,
                    bgcolor=p.accent if sel else p.bg_chat,
                    border=ft.Border.all(2, p.accent if sel else ft.Colors.TRANSPARENT),
                    alignment=ft.Alignment.CENTER,
                    content=ft.Text(ic or 'Aa', size=17 if ic else 12, weight=ft.FontWeight.W_700 if not ic else ft.FontWeight.W_400, color=ft.Colors.WHITE if sel else p.text),
                ),
            ))
        icon_row.controls = cells
        if not initial:
            icon_row.update()

    def pick_icon(self, ic, icon_row):
        self.selected_icon = ic
        self.build_icon_picker(icon_row)

    def build_color_picker(self, color_row, initial=False):
        p = self.p
        cells = []
        for c in COLORS:
            sel = c == self.selected_color
            cells.append(ft.GestureDetector(
                on_tap=lambda e, col=c: self.pick_color(col, color_row),
                content=ft.Container(
                    width=28, height=28, border_radius=14, bgcolor=c,
                    border=ft.Border.all(2, p.text if sel else ft.Colors.TRANSPARENT),
                ),
            ))
        color_row.controls = cells
        if not initial:
            color_row.update()

    def pick_color(self, c, color_row):
        self.selected_color = c
        self.build_color_picker(color_row)

    async def save_chat_modal(self, name_field, dlg):
        name = name_field.value.strip()
        if not name:
            return
        if self.editing_chat_id:
            chat = self.state.chat_by_id(self.editing_chat_id)
            if chat:
                chat['name'] = name
                chat['color'] = self.selected_color
                chat['icon'] = self.selected_icon
            self.chat_topbar.content = self.build_chat_topbar()
        else:
            chat = {'id': uid('c'), 'name': name, 'color': self.selected_color, 'icon': self.selected_icon}
            self.state.chats.append(chat)
        await self.state.save()
        self.page.pop_dialog(dlg)
        self.render_chat_list()
        if not self.editing_chat_id:
            self.open_chat(chat['id'])

    def confirm_delete_chat(self):
        if len(self.state.chats) <= 1:
            self.toast('Нужен хотя бы один чат', error=True)
            return
        p = self.p
        dlg = ft.AlertDialog(
            title=ft.Text('Удалить чат?', size=16, weight=ft.FontWeight.W_700, color=p.text),
            content=ft.Text('Чат и все записи в нём будут удалены.', size=14, color=p.text_soft),
            bgcolor=p.modal_bg,
            actions=[
                ft.TextButton('Отмена', style=ft.ButtonStyle(color=p.text_soft), on_click=lambda e: self.page.pop_dialog(dlg)),
                ft.TextButton('Удалить', style=ft.ButtonStyle(color=p.danger), on_click=lambda e: self.delete_chat(dlg)),
            ],
        )
        self.page.show_dialog(dlg)

    async def delete_chat(self, dlg):
        self.page.pop_dialog(dlg)
        for e in self.state.entries_for(self.current_chat_id):
            self.media.remove(e.get('media', ''))
        self.state.entries = [e for e in self.state.entries if e['chatId'] != self.current_chat_id]
        self.state.chats = [c for c in self.state.chats if c['id'] != self.current_chat_id]
        await self.state.save()
        self.close_chat()

    # ---------------- SETTINGS ----------------

    async def set_theme(self, theme):
        self.state.theme = theme
        await self.state.save()
        self.apply_theme()

    # ---------------- MISC ----------------

    def toast(self, msg, error=False):
        sb = ft.SnackBar(
            ft.Text(msg, color='#FFD9D9' if error else self.p.text),
            open=True,
            bgcolor='#3A2020' if error else self.p.bg_chat,
            duration=2500,
        )
        self.page.show_dialog(sb)


async def main(page: ft.Page):
    page.title = 'TN'
    page.padding = 0
    page.theme_mode = ft.ThemeMode.LIGHT
    if page.platform not in (ft.PagePlatform.ANDROID, ft.PagePlatform.IOS):
        try:
            page.width = 420
            page.height = 860
        except Exception:
            pass
    app = NotesApp(page)
    await app.init()


if __name__ == '__main__':
    ft.run(main)