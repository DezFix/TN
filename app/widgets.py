import re

import flet as ft


def initials(name):
    return name.strip()[:1].upper() if name.strip() else '?'


def fmt_time(ts):
    import datetime
    return datetime.datetime.fromtimestamp(ts / 1000).strftime('%H:%M')


def fmt_day(ts, tr):
    import datetime
    d = datetime.datetime.fromtimestamp(ts / 1000)
    today = datetime.date.today()
    if d.date() == today:
        return tr('today')
    if d.date() == today - datetime.timedelta(days=1):
        return tr('yesterday')
    return d.strftime('%d %B').lstrip('0')


def avatar(chat, size=50, font_size=None, p=None):
    content = chat.get('icon') or initials(chat.get('name', ''))
    return ft.Container(
        width=size,
        height=size,
        border_radius=size / 2,
        bgcolor=chat.get('color', '#2AABEE'),
        alignment=ft.Alignment.CENTER,
        content=ft.Text(
            content,
            color=ft.Colors.WHITE,
            size=font_size or (size * 0.4 if chat.get('icon') else size * 0.38),
            weight=ft.FontWeight.W_600,
        ),
    )


def day_pill(text, p):
    return ft.Container(
        bgcolor=ft.Colors.with_opacity(0.16, '#7F8C98'),
        border_radius=10,
        padding=ft.Padding.symmetric(horizontal=11, vertical=4),
        margin=ft.margin.symmetric(vertical=8),
        content=ft.Text(text, size=11.5, color=p.text_soft, weight=ft.FontWeight.W_500),
    )


def hashtag_text(text, p, size=14.5):
    spans = []
    last = 0
    for m in re.finditer(r'#[\wа-яА-ЯёЁ]+', text):
        if m.start() > last:
            spans.append(ft.TextSpan(text[last:m.start()]))
        spans.append(ft.TextSpan(
            m.group(0),
            style=ft.TextStyle(color=p.accent_dk, weight=ft.FontWeight.W_600),
        ))
        last = m.end()
    if last < len(text):
        spans.append(ft.TextSpan(text[last:]))
    if not spans:
        spans.append(ft.TextSpan(text))
    return ft.Text(spans=spans, size=size, color=p.text, selectable=True)


def chat_preview(entry, tr):
    t = entry.get('type')
    if t == 'text':
        return entry.get('text', '')[:60]
    if t == 'image':
        return tr('photo')
    if t == 'audio':
        return tr('voice_preview', entry.get('duration', 0))
    if t == 'video':
        return tr('video_preview')
    if t == 'todo':
        items = entry.get('items') or []
        done = sum(1 for i in items if i.get('done'))
        return tr('todo_progress', done, len(items))
    return ''


def build_chat_row(chat, state, p, on_open, tr):
    entries = state.entries_for(chat['id'])
    last = entries[-1] if entries else None
    return ft.GestureDetector(
        on_tap=lambda e: on_open(chat['id']),
        content=ft.Container(
            bgcolor=p.bg_list,
            padding=ft.Padding.symmetric(horizontal=16, vertical=10),
            border=ft.Border.only(bottom=ft.BorderSide(1, p.divider)),
            content=ft.Row(
                spacing=12,
                controls=[
                    avatar(chat),
                    ft.Column(
                        expand=True,
                        spacing=2,
                        controls=[
                            ft.Row(
                                controls=[
                                    ft.Text(chat['name'], size=15.5, weight=ft.FontWeight.W_600, color=p.text, expand=True, overflow=ft.TextOverflow.ELLIPSIS),
                                    ft.Text(fmt_time(last['ts']) if last else '', size=12, color=p.text_faint),
                                ],
                            ),
                            ft.Row(
                                controls=[
                                    ft.Text(chat_preview(last, tr) if last else tr('no_entries'), size=13.5, color=p.text_soft, expand=True, overflow=ft.TextOverflow.ELLIPSIS, max_lines=1),
                                    ft.Container(
                                        bgcolor=p.accent,
                                        border_radius=10,
                                        padding=ft.Padding.symmetric(horizontal=5, vertical=2),
                                        content=ft.Text(str(len(entries)), size=11, color=ft.Colors.WHITE, weight=ft.FontWeight.W_600),
                                    ) if entries else ft.Container(),
                                ],
                            ),
                        ],
                    ),
                ],
            ),
        ),
    )


def build_forward_row(chat, p, on_pick):
    return ft.GestureDetector(
        on_tap=lambda e: on_pick(chat),
        content=ft.Container(
            padding=ft.Padding.symmetric(vertical=8, horizontal=4),
            content=ft.Row(
                spacing=10,
                controls=[
                    avatar(chat, size=38),
                    ft.Text(chat['name'], size=15, weight=ft.FontWeight.W_600, color=p.text, expand=True),
                ],
            ),
        ),
    )