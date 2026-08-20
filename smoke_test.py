import asyncio

import flet as ft
import flet.controls.base_control as bc

from main import NotesApp


class FakePage:
    def __init__(self):
        self.theme_mode = None
        self.bgcolor = None
        self.theme = None
        self.floating_action_button = None
        self.dialogs = []
        self.title = ''
        self.padding = 0
        self.platform = 'windows'
        self.width = None
        self.height = None
        self.clipboard = FakeClipboard()
        self.updates = 0

    def add(self, control):
        pass

    def update(self, *args):
        self.updates += 1

    def show_dialog(self, dialog):
        self.dialogs.append(dialog)
        dialog.open = True

    def pop_dialog(self, dialog=None):
        if dialog is None:
            if self.dialogs:
                self.dialogs.pop()
        elif dialog in self.dialogs:
            self.dialogs.remove(dialog)

    def run_task(self, handler, *args, **kwargs):
        return asyncio.ensure_future(handler(*args, **kwargs))


class FakeClipboard:
    def __init__(self):
        self.value = ''

    async def set(self, text):
        self.value = text

    async def get(self):
        return self.value


fake_page = FakePage()
bc.BaseControl.page = property(lambda self: fake_page)


def check(cond, name):
    print(('OK  ' if cond else 'FAIL') + '  ' + name)
    if not cond:
        raise SystemExit(1)


async def main():
    app = NotesApp(fake_page)
    await app.init()
    check(fake_page.theme_mode == ft.ThemeMode.LIGHT, 'init: light theme')
    check(len(app.state.chats) == 0, 'init: no default chats')
    check(len(fake_page.dialogs) == 0, 'init: no dialogs open')
    check(not app.screen_chat.visible and not app.screen_settings.visible, 'init: chat/settings hidden')

    app.open_chat_modal(None)
    check(len(fake_page.dialogs) == 1, 'create chat modal opened')

    fake_page.pop_dialog()
    check(len(fake_page.dialogs) == 0, 'create chat modal closed (Отмена)')

    app.open_chat_modal(None)
    check(len(fake_page.dialogs) == 1, 'create chat modal reopened')

    app.selected_icon = '💡'
    app.selected_color = '#D6538B'
    name_field = fake_page.dialogs[0].content.controls[0]
    name_field.value = 'Новый чат'
    await app.save_chat_modal(name_field, fake_page.dialogs[0])
    check(len(app.state.chats) == 1, 'create chat: added')
    check(app.current_chat_id == app.state.chats[-1]['id'], 'create chat: opened new chat')
    check(app.state.chats[-1]['icon'] == '💡', 'create chat: icon saved')

    app.open_chat(app.state.chats[0]['id'])
    app.text_input.value = 'Тест #важно'
    await app.send_text()
    check(len(app.state.entries) == 1, 'send text: entry added')
    check(app.state.entries[0]['tags'] == ['важно'], 'send text: tags extracted')
    check(fake_page.updates > 0, 'send text: page updated')

    app.open_chat_modal(None)
    name_field2 = fake_page.dialogs[0].content.controls[0]
    name_field2.value = 'Второй чат'
    await app.save_chat_modal(name_field2, fake_page.dialogs[0])
    check(len(app.state.chats) == 2, 'second chat added')

    await app.set_theme('dark')
    check(app.state.theme == 'dark', 'theme: state dark')
    check(fake_page.theme_mode == ft.ThemeMode.DARK, 'theme: page mode DARK')
    check(app.p.name == 'dark', 'theme: palette switched')
    check(app.screen_list.bgcolor == '#1C232C', 'theme: screen bg updated')

    await app.set_theme('light')
    check(app.p.name == 'light', 'theme: back to light')

    entry = app.state.entries[0]
    app.open_ctx_menu(entry)
    check(len(fake_page.dialogs) == 1, 'ctx menu: sheet shown')

    sheet = fake_page.dialogs[0]
    fake_page.pop_dialog()
    check(len(fake_page.dialogs) == 0, 'ctx menu: sheet closed')

    app.open_forward(entry)
    check(len(fake_page.dialogs) == 1, 'forward: dialog shown')
    await app.do_forward(entry, app.state.chats[0])
    check(len(app.state.entries) == 2, 'forward: entry copied')

    app.open_chat(app.state.chats[0]['id'])
    app.confirm_delete_chat()
    check(len(fake_page.dialogs) >= 1, 'delete chat: confirm dialog')
    await app.delete_chat(fake_page.dialogs[0])
    check(len(app.state.chats) == 1, 'delete chat: chat removed')

    print('ALL CHECKS PASSED')


asyncio.run(main())