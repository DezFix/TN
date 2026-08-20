class Palette:
    def __init__(self, name, accent, accent_dk, bg, bg_list, bg_chat, bubble_own, bubble_border,
                 text, text_soft, text_faint, divider, danger, row_active, modal_bg):
        self.name = name
        self.accent = accent
        self.accent_dk = accent_dk
        self.bg = bg
        self.bg_list = bg_list
        self.bg_chat = bg_chat
        self.bubble_own = bubble_own
        self.bubble_border = bubble_border
        self.text = text
        self.text_soft = text_soft
        self.text_faint = text_faint
        self.divider = divider
        self.danger = danger
        self.row_active = row_active
        self.modal_bg = modal_bg


LIGHT = Palette(
    name='light',
    accent='#2AABEE', accent_dk='#1E96D6',
    bg='#FFFFFF', bg_list='#FFFFFF', bg_chat='#EDF2F5',
    bubble_own='#E4F3FF', bubble_border='#D3EAFB',
    text='#0F1721', text_soft='#7C8A97', text_faint='#A9B4BE',
    divider='#E6E9EC', danger='#E05353', row_active='#F5F7F9', modal_bg='#FFFFFF',
)

DARK = Palette(
    name='dark',
    accent='#4EA4F6', accent_dk='#71B8F8',
    bg='#1C232C', bg_list='#1C232C', bg_chat='#262E39',
    bubble_own='#2F4A63', bubble_border='#3A5772',
    text='#EDF1F5', text_soft='#A2ACB6', text_faint='#717B85',
    divider='#323B46', danger='#F07575', row_active='#28313C', modal_bg='#262E39',
)


def palette_for(theme):
    return DARK if theme == 'dark' else LIGHT