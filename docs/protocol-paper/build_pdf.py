#!/usr/bin/env python3
"""Build the Daimon protocol paper PDFs from the Markdown sources.

    python build_pdf.py [--fonts DIR] [--only EN|IT] [--out DIR]

Reproduces the layout of the v0.1 release (A4, DejaVu Serif body, DejaVu Sans
headings, navy cover with the logo, table of contents on page 2, footer page
numbers starting at 1 on the first body page). Requires `reportlab`, `pikepdf`
and the DejaVu font family (https://dejavu-fonts.github.io/, the `ttf`
directory of the release archive). Output files are linearized and carry the
document metadata; the PDF content is a pure function of the sources, so a
release must be rebuilt only when the sources change.
"""
import argparse
import io
import os
import re
import sys
import tempfile

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, HRFlowable, ListFlowable,
                                ListItem, NextPageTemplate, PageBreak,
                                PageTemplate, Paragraph, Preformatted, Spacer,
                                Table, TableStyle)
from reportlab.platypus.tableofcontents import TableOfContents

HERE = os.path.dirname(os.path.abspath(__file__))
VERSION = "v0.2"

EDITIONS = {
    "EN": {
        "source": "protocol_paper_EN.md",
        "output": "Daimon_Protocol_Paper_EN_v0.2.pdf",
        "title": "Daimon (DMN) — Protocol paper",
        "subject": "An ownerless, DAO-governed deflationary protocol on BNB Chain",
        "subtitle": ["An ownerless, DAO-governed deflationary", "protocol on BNB Chain"],
        "taglines": ["No owner · No mint", "21 billion supply floor", "7-day public timelock"],
        "cover_line": "Protocol paper · " + VERSION,
        "toc_title": "Contents",
        "toc_note": "Numbers refer to the page numbering printed in the footer.",
        "footer": "Daimon (DMN) · Protocol paper " + VERSION,
    },
    "IT": {
        "source": "protocol_paper_IT.md",
        "output": "Daimon_Protocol_Paper_IT_v0.2.pdf",
        "title": "Daimon (DMN) — Protocol paper (versione italiana)",
        "subject": "Protocollo deflazionario senza proprietario, governato da una DAO, su BNB Chain",
        "subtitle": ["Un protocollo deflazionario senza proprietario,", "governato da una DAO, su BNB Chain"],
        "taglines": ["Nessun proprietario · Nessuna emissione", "Floor di supply a 21 miliardi", "Timelock pubblico di 7 giorni"],
        "cover_line": "Protocol paper · " + VERSION + " · Versione italiana",
        "toc_title": "Indice",
        "toc_note": "I numeri si riferiscono alla numerazione a piè di pagina.",
        "footer": "Daimon (DMN) · Protocol paper " + VERSION + " · versione italiana",
    },
}
KEYWORDS = "Daimon, DMN, DAO, BNB Chain, DeFi, governance, staking, deflationary"
AUTHOR = "Daimon DAO"
LOGO = os.path.join(HERE, "..", "..", "social-assets", "logo-512.png")

# ---- palette (matches the v0.1 release) ----
NAVY = colors.HexColor("#0B1230")
GOLD = colors.HexColor("#C9A23F")
INK = colors.HexColor("#1B1B1F")
MUTED = colors.HexColor("#6B7280")
RULE = colors.HexColor("#D9DCE3")
CODE_FG = colors.HexColor("#E8EAF0")
INLINE_BG = colors.HexColor("#EEF0F4")
LINK = colors.HexColor("#1F3A93")
ROW_ALT = colors.HexColor("#F4F5F8")

PAGE_W, PAGE_H = A4
MARGIN_X = 57
MARGIN_TOP = 62
MARGIN_BOTTOM = 62
FRAME_W = PAGE_W - 2 * MARGIN_X


# --------------------------------------------------------------------------
# Fonts
# --------------------------------------------------------------------------
def find_font_dir(explicit):
    candidates = [explicit, os.environ.get("DEJAVU_DIR"),
                  "/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/dejavu",
                  "C:/Windows/Fonts"]
    for c in candidates:
        if c and os.path.isfile(os.path.join(c, "DejaVuSerif.ttf")):
            return c
    sys.exit("DejaVu fonts not found: pass --fonts DIR (the ttf/ directory of the DejaVu release)")


def register_fonts(font_dir):
    names = ["DejaVuSerif", "DejaVuSerif-Bold", "DejaVuSerif-Italic", "DejaVuSerif-BoldItalic",
             "DejaVuSans", "DejaVuSans-Bold", "DejaVuSans-Oblique", "DejaVuSans-BoldOblique",
             "DejaVuSans-ExtraLight", "DejaVuSansMono", "DejaVuSansMono-Bold"]
    for n in names:
        pdfmetrics.registerFont(TTFont(n, os.path.join(font_dir, n + ".ttf")))
    pdfmetrics.registerFontFamily("DejaVuSerif", normal="DejaVuSerif", bold="DejaVuSerif-Bold",
                                  italic="DejaVuSerif-Italic", boldItalic="DejaVuSerif-BoldItalic")
    pdfmetrics.registerFontFamily("DejaVuSans", normal="DejaVuSans", bold="DejaVuSans-Bold",
                                  italic="DejaVuSans-Oblique", boldItalic="DejaVuSans-BoldOblique")
    pdfmetrics.registerFontFamily("DejaVuSansMono", normal="DejaVuSansMono", bold="DejaVuSansMono-Bold",
                                  italic="DejaVuSansMono", boldItalic="DejaVuSansMono-Bold")
    from reportlab import rl_config
    rl_config.canvas_basefontname = "DejaVuSans"  # no unembedded Helvetica in the file


# --------------------------------------------------------------------------
# Styles
# --------------------------------------------------------------------------
def make_styles():
    s = {}
    s["body"] = ParagraphStyle("body", fontName="DejaVuSerif", fontSize=9.4, leading=12.8,
                               textColor=INK, spaceAfter=6.5)
    s["h1"] = ParagraphStyle("h1", fontName="DejaVuSans-Bold", fontSize=15, leading=19,
                             textColor=NAVY, spaceBefore=16, spaceAfter=9, keepWithNext=1)
    s["h2"] = ParagraphStyle("h2", fontName="DejaVuSans-Bold", fontSize=11.3, leading=14.5,
                             textColor=NAVY, spaceBefore=12, spaceAfter=4.5, keepWithNext=1)
    s["h3"] = ParagraphStyle("h3", fontName="DejaVuSans-Bold", fontSize=9.8, leading=12.5,
                             textColor=NAVY, spaceBefore=10, spaceAfter=3.5, keepWithNext=1)
    s["li"] = ParagraphStyle("li", parent=s["body"], spaceAfter=2.5)
    s["quote"] = ParagraphStyle("quote", parent=s["body"], fontName="DejaVuSerif-Italic",
                                textColor=colors.HexColor("#3A3A44"), leftIndent=4, spaceAfter=0)
    s["code"] = ParagraphStyle("code", fontName="DejaVuSansMono", fontSize=7.3, leading=9.4,
                               textColor=CODE_FG)
    s["cell"] = ParagraphStyle("cell", fontName="DejaVuSans", fontSize=7.9, leading=10.2, textColor=INK)
    s["cellh"] = ParagraphStyle("cellh", fontName="DejaVuSans-Bold", fontSize=7.9, leading=10.2, textColor=GOLD)
    s["toc_title"] = ParagraphStyle("toc_title", fontName="DejaVuSans-Bold", fontSize=15, leading=19,
                                    textColor=NAVY, spaceAfter=8)
    s["toc0"] = ParagraphStyle("toc0", fontName="DejaVuSans-Bold", fontSize=8, leading=9.8,
                               textColor=NAVY, spaceBefore=2.8)
    s["toc1"] = ParagraphStyle("toc1", fontName="DejaVuSerif", fontSize=6.9, leading=8.4,
                               textColor=INK, leftIndent=14)
    s["toc_note"] = ParagraphStyle("toc_note", fontName="DejaVuSerif-Italic", fontSize=6.8, leading=9,
                                   textColor=MUTED, spaceBefore=10)
    s["closing"] = ParagraphStyle("closing", parent=s["body"], fontSize=8.6, leading=11.5)
    return s


# --------------------------------------------------------------------------
# Inline Markdown -> ReportLab paragraph markup
# --------------------------------------------------------------------------
def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def inline(text, mono_size=7.6, in_table=False):
    text = esc(text)
    codes = []

    def keep_code(m):
        codes.append(m.group(1))
        return "\x00%d\x00" % (len(codes) - 1)

    text = re.sub(r"`([^`]+)`", keep_code, text)
    text = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
                  lambda m: '<link href="%s" color="#1F3A93">%s</link>' % (m.group(2), m.group(1)), text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", text)

    def put_code(m):
        c = codes[int(m.group(1))]
        size = mono_size
        if in_table and len(c) > 40:
            size = 6.3
        return ('<font face="DejaVuSansMono" size="%s" backColor="#EEF0F4"> %s </font>' % (size, c)
                if not in_table else '<font face="DejaVuSansMono" size="%s">%s</font>' % (size, c))

    text = re.sub("\x00(\\d+)\x00", put_code, text)
    return text


# --------------------------------------------------------------------------
# Block parser
# --------------------------------------------------------------------------
class Heading(Paragraph):
    def __init__(self, text, style, level, number, title):
        Paragraph.__init__(self, text, style)
        self.toc_level = level
        self.toc_number = number
        self.toc_title = title


def code_block(lines, st):
    txt = "\n".join(lines)
    pre = Preformatted(txt, st["code"])
    t = Table([[pre]], colWidths=[FRAME_W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), NAVY),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    t.spaceBefore = 3
    t.spaceAfter = 9
    return t


def table_block(rows, st):
    def split_row(line):
        line = line.strip()
        if line.startswith("|"):
            line = line[1:]
        if line.endswith("|"):
            line = line[:-1]
        return [c.strip() for c in line.split("|")]

    header = split_row(rows[0])
    body = [split_row(r) for r in rows[2:]]
    ncol = len(header)
    body = [r + [""] * (ncol - len(r)) for r in body]
    # column widths proportional to the longest cell, bounded
    lens = []
    for c in range(ncol):
        m = max([len(header[c])] + [len(r[c]) for r in body])
        lens.append(min(max(m, 6), 70))
    total = float(sum(lens))
    widths = [FRAME_W * l / total for l in lens]
    data = [[Paragraph(inline(h, in_table=True), st["cellh"]) for h in header]]
    for r in body:
        data.append([Paragraph(inline(c, in_table=True), st["cell"]) for c in r])
    t = Table(data, colWidths=widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, -1), (-1, -1), 0.5, RULE),
        ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            style.append(("BACKGROUND", (0, i), (-1, i), ROW_ALT))
    t.setStyle(TableStyle(style))
    t.spaceBefore = 3
    t.spaceAfter = 9
    return t


def quote_block(lines, st):
    p = Paragraph(inline(" ".join(lines)), st["quote"])
    t = Table([[p]], colWidths=[FRAME_W - 10])
    t.setStyle(TableStyle([
        ("LINEBEFORE", (0, 0), (0, -1), 2, GOLD),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))
    t.hAlign = "LEFT"
    t.spaceBefore = 2
    t.spaceAfter = 8
    return t


def list_block(items, ordered, st):
    flow = [ListItem(Paragraph(inline(" ".join(it)), st["li"]), leftIndent=16) for it in items]
    kw = dict(bulletFontName="DejaVuSans", bulletFontSize=8, leftIndent=16, bulletOffsetY=0)
    if ordered:
        lf = ListFlowable(flow, bulletType="1", bulletFormat="%s.", **kw)
    else:
        lf = ListFlowable(flow, bulletType="bullet", start="•", **kw)
    lf.spaceAfter = 5
    return lf


HEADING_RE = re.compile(r"^(#{1,3})\s+(.*)$")
NUM_RE = re.compile(r"^(\d+(?:\.\d+)*)\.?\s+(.*)$")


def parse(md, st):
    lines = md.replace("\r\n", "\n").split("\n")
    # skip the source header: everything before the first numbered H1
    start = next(i for i, l in enumerate(lines) if re.match(r"^# \d+\.", l))
    lines = lines[start:]
    story = []
    i = 0
    para = []
    closing = False

    def flush_para():
        if para:
            style = st["closing"] if closing else st["body"]
            story.append(Paragraph(inline(" ".join(para)), style))
            del para[:]

    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if stripped == "":
            flush_para()
            i += 1
            continue
        if stripped.startswith("```"):
            flush_para()
            block = []
            i += 1
            while i < n and not lines[i].strip().startswith("```"):
                block.append(lines[i].rstrip("\n"))
                i += 1
            i += 1
            story.append(code_block(block, st))
            continue
        m = HEADING_RE.match(line)
        if m:
            flush_para()
            level = len(m.group(1))
            text = m.group(2).strip()
            nm = NUM_RE.match(text)
            number, title = (nm.group(1), nm.group(2)) if nm else ("", text)
            style = {1: st["h1"], 2: st["h2"], 3: st["h3"]}[level]
            story.append(Heading(inline(text), style, level, number, title))
            i += 1
            continue
        if stripped == "---":
            flush_para()
            # the closing block (repository / audit reference / release line)
            rest = [l for l in lines[i + 1:] if l.strip()]
            if rest and not any(HEADING_RE.match(l) for l in rest):
                closing = True
                story.append(Spacer(1, 10))
                story.append(HRFlowable(width="100%", thickness=0.5, color=RULE, spaceAfter=10))
            else:
                story.append(HRFlowable(width="100%", thickness=0.5, color=RULE, spaceBefore=8, spaceAfter=10))
            i += 1
            continue
        if stripped.startswith("|"):
            flush_para()
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(lines[i])
                i += 1
            story.append(table_block(rows, st))
            continue
        if stripped.startswith(">"):
            flush_para()
            q = []
            while i < n and lines[i].strip().startswith(">"):
                q.append(lines[i].strip()[1:].strip())
                i += 1
            story.append(quote_block(q, st))
            continue
        bm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if bm and not bm.group(1):
            flush_para()
            ordered = bm.group(2)[0].isdigit()
            items = []
            while i < n:
                bm = re.match(r"^([-*]|\d+\.)\s+(.*)$", lines[i])
                if bm:
                    items.append([bm.group(2)])
                    i += 1
                    while i < n and lines[i].startswith("  ") and lines[i].strip():
                        items[-1].append(lines[i].strip())
                        i += 1
                else:
                    break
            story.append(list_block(items, ordered, st))
            continue
        para.append(stripped)
        i += 1
        if closing:
            flush_para()  # the closing block: one line, one paragraph
    flush_para()
    return story


# --------------------------------------------------------------------------
# Document template: cover, TOC, body with footer, bookmarks
# --------------------------------------------------------------------------
class PaperDoc(BaseDocTemplate):
    def __init__(self, filename, edition, **kw):
        BaseDocTemplate.__init__(self, filename, pagesize=A4, leftMargin=MARGIN_X, rightMargin=MARGIN_X,
                                 topMargin=MARGIN_TOP, bottomMargin=MARGIN_BOTTOM, **kw)
        self.edition = edition
        frame = Frame(MARGIN_X, MARGIN_BOTTOM, FRAME_W, PAGE_H - MARGIN_TOP - MARGIN_BOTTOM,
                      id="body", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
        toc_frame = Frame(MARGIN_X, 40, FRAME_W, PAGE_H - 40 - 44,
                          id="toc", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
        self.addPageTemplates([
            PageTemplate(id="Cover", frames=[frame], onPage=self.draw_cover),
            PageTemplate(id="TOC", frames=[toc_frame], onPage=lambda c, d: None),
            PageTemplate(id="Body", frames=[frame], onPage=self.draw_footer),
        ])
        self._keys = 0
        self._body_start = None

    def _startBuild(self, *a, **kw):
        # multiBuild runs several passes; the body may start on a different
        # physical page once the table of contents has its final length
        self._keys = 0
        self._body_start = None
        BaseDocTemplate._startBuild(self, *a, **kw)

    def body_page(self):
        if self._body_start is None:
            return 1
        return self.page - self._body_start + 1

    def afterFlowable(self, flowable):
        if isinstance(flowable, Heading) and flowable.toc_level <= 2:
            num = flowable.toc_number
            text = '<font color="#C9A23F">%s</font> %s' % (esc(num), inline(flowable.toc_title))
            self.notify("TOCEntry", (flowable.toc_level - 1, text, self.body_page()))
            key = "h%d" % self._keys
            self._keys += 1
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry("%s %s" % (num, flowable.toc_title), key,
                                      level=flowable.toc_level - 1, closed=False)

    def draw_footer(self, canv, doc):
        if self._body_start is None:
            self._body_start = self.page
        canv.saveState()
        canv.setFont("DejaVuSans", 6.8)
        canv.setFillColor(MUTED)
        canv.drawString(MARGIN_X, 34, self.edition["footer"])
        canv.drawRightString(PAGE_W - MARGIN_X, 34, str(self.body_page()))
        canv.restoreState()

    def draw_cover(self, canv, doc):
        e = self.edition
        canv.saveState()
        canv.setFillColor(NAVY)
        canv.rect(0, 0, PAGE_W, PAGE_H, stroke=0, fill=1)
        logo = prepare_logo()
        if logo:
            d = 68
            canv.drawImage(logo, PAGE_W / 2 - d / 2, 536 - d / 2, d, d, mask="auto")
        canv.setFillColor(GOLD)
        canv.setFont("DejaVuSans-Bold", 30)
        canv.drawCentredString(PAGE_W / 2, 447, "DAIMON")
        canv.setFont("DejaVuSans", 9)
        canv.drawCentredString(PAGE_W / 2, 429, "D  M  N")
        canv.setStrokeColor(GOLD)
        canv.setLineWidth(0.8)
        canv.line(PAGE_W / 2 - 16, 404, PAGE_W / 2 + 16, 404)
        canv.setFillColor(colors.HexColor("#C8CBD6"))
        canv.setFont("DejaVuSans-ExtraLight", 9.5)
        y = 374
        for l in e["subtitle"]:
            canv.drawCentredString(PAGE_W / 2, y, l)
            y -= 15
        canv.setFillColor(GOLD)
        canv.setFont("DejaVuSans-Bold", 7)
        y = 312
        for l in e["taglines"]:
            canv.drawCentredString(PAGE_W / 2, y, l)
            y -= 16
        canv.setFillColor(colors.HexColor("#7F8497"))
        canv.setFont("DejaVuSans", 6)
        canv.drawCentredString(PAGE_W / 2, 94, e["cover_line"])
        canv.drawCentredString(PAGE_W / 2, 82, "github.com/daimon-dao")
        canv.restoreState()


_logo_cache = {}


def prepare_logo():
    """The logo PNG is a circle on a square; give the square a circular alpha
    mask so it sits on the navy cover without a box."""
    if "path" in _logo_cache:
        return _logo_cache["path"]
    path = None
    try:
        from PIL import Image, ImageDraw
        img = Image.open(LOGO).convert("RGBA")
        w, h = img.size
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).ellipse((1, 1, w - 2, h - 2), fill=255)
        alpha = img.getchannel("A")
        from PIL import ImageChops
        img.putalpha(ImageChops.multiply(alpha, mask))
        fd, path = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        img.save(path)
    except Exception as ex:  # no logo is better than a broken build
        print("logo skipped:", ex)
        path = None
    _logo_cache["path"] = path
    return path


def build(edition_key, font_dir, out_dir):
    e = EDITIONS[edition_key]
    st = make_styles()
    md = io.open(os.path.join(HERE, e["source"]), encoding="utf-8").read()
    story = [NextPageTemplate("TOC"), PageBreak()]
    toc = TableOfContents()
    toc.levelStyles = [st["toc0"], st["toc1"]]
    toc.dotsMinLevel = 100
    toc.tableStyle = TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ])
    story += [Paragraph(e["toc_title"], st["toc_title"]), toc,
              Paragraph(e["toc_note"], st["toc_note"]),
              NextPageTemplate("Body"), PageBreak()]
    story += parse(md, st)

    out = os.path.join(out_dir, e["output"])
    tmp = out + ".tmp"
    doc = PaperDoc(tmp, e, title=e["title"], author=AUTHOR, subject=e["subject"],
                   keywords=KEYWORDS, creator=AUTHOR, initialFontName="DejaVuSans")
    doc.multiBuild(story)

    import pikepdf
    with pikepdf.open(tmp) as pdf:
        with pdf.open_metadata(set_pikepdf_as_editor=False) as meta:
            pass
        pdf.docinfo["/Title"] = e["title"]
        pdf.docinfo["/Subject"] = e["subject"]
        pdf.docinfo["/Keywords"] = KEYWORDS
        pdf.docinfo["/Author"] = AUTHOR
        pdf.docinfo["/Creator"] = AUTHOR
        pdf.docinfo["/Producer"] = AUTHOR
        if "/Metadata" in pdf.Root:
            del pdf.Root["/Metadata"]
        pdf.save(out, linearize=True, fix_metadata_version=False)
    os.remove(tmp)
    print("wrote", out, "pages:", doc.page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", help="directory holding the DejaVu .ttf files")
    ap.add_argument("--only", choices=["EN", "IT"])
    ap.add_argument("--out", default=HERE)
    a = ap.parse_args()
    register_fonts(find_font_dir(a.fonts))
    for k in (["EN", "IT"] if not a.only else [a.only]):
        build(k, a.fonts, a.out)


if __name__ == "__main__":
    main()
