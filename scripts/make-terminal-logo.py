#!/usr/bin/env python3
"""Turn a brand image into a truecolor half-block pixel logo for fastfetch.

Authoring-time tool (needs Pillow); its output, `logo.txt`, is committed, so
nothing here runs at login. Each terminal cell carries two vertical pixels
(upper half block, foreground over background), so a COLS-wide logo is
COLS/2 rows tall. Transparent pixels stay transparent, so the logo sits on any
terminal background. Used for the alt-v3 layer (dotfiles/terminal/_alt-v3).

usage: make-terminal-logo.py <image> <logo.txt> [cols=28]
"""
import sys

from PIL import Image

ALPHA_CROP = 24      # alpha above this counts as content when trimming margins
ALPHA_OPAQUE = 110   # alpha below this renders as an empty cell half
DEFAULT_COLS = 28
RESET = "\x1b[0m"


def fg(rgb):
    return f"\x1b[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m"


def bg(rgb):
    return f"\x1b[48;2;{rgb[0]};{rgb[1]};{rgb[2]}m"


def square_pixels(path, cols):
    """The image trimmed to its content, centred on a transparent square."""
    image = Image.open(path).convert("RGBA")
    box = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CROP else 0).getbbox()
    if box is None:
        raise SystemExit(f"{path}: image is fully transparent")
    image = image.crop(box)
    side = max(image.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
    return canvas.resize((cols, cols), Image.LANCZOS)


def render(pixels, cols):
    def at(x, y):
        r, g, b, a = pixels.getpixel((x, y))
        return None if a < ALPHA_OPAQUE else (r, g, b)

    rows = []
    for y in range(0, cols, 2):
        cells = []
        for x in range(cols):
            top, bottom = at(x, y), at(x, y + 1)
            if top and bottom:
                cells.append(f"{fg(top)}{bg(bottom)}▀{RESET}")
            elif top:
                cells.append(f"{fg(top)}▀{RESET}")
            elif bottom:
                cells.append(f"{fg(bottom)}▄{RESET}")
            else:
                cells.append(" ")
        rows.append("".join(cells).rstrip())
    return "\n".join(rows) + "\n"


def main(argv):
    if len(argv) not in (3, 4):
        raise SystemExit(__doc__)
    cols = int(argv[3]) if len(argv) == 4 else DEFAULT_COLS
    if cols % 2:
        raise SystemExit("cols must be even")
    with open(argv[2], "w", encoding="utf-8") as out:
        out.write(render(square_pixels(argv[1], cols), cols))


if __name__ == "__main__":
    main(sys.argv)
