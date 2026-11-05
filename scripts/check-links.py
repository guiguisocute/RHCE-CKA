#!/usr/bin/env python3
"""检查仓库内 Markdown / HTML 的相对链接是否指向存在的文件。

用法：python3 scripts/check-links.py [路径 ...]   # 默认检查 README.md、index.html、notes/、labs/、journal/
只检查相对链接（不访问网络），会忽略 http(s)://、mailto: 和纯锚点 #xxx。
"""
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ["README.md", "index.html", "notes", "labs", "journal", "references/README.md"]
MD_LINK = re.compile(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HTML_LINK = re.compile(r"""(?:href|src)=["']([^"']+)["']""")
SKIP = ("http://", "https://", "mailto:", "#", "javascript:", "data:")


def iter_files(args):
    for a in args or DEFAULT:
        p = (ROOT / a) if not Path(a).is_absolute() else Path(a)
        if p.is_dir():
            yield from sorted(x for x in p.rglob("*") if x.suffix in (".md", ".html"))
        elif p.exists():
            yield p


def strip_code(text):
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    return re.sub(r"`[^`\n]*`", "", text)


def main(argv):
    bad = 0
    count = 0
    for f in iter_files(argv):
        text = f.read_text(encoding="utf-8")
        pattern = HTML_LINK if f.suffix == ".html" else MD_LINK
        body = text if f.suffix == ".html" else strip_code(text)
        for m in pattern.finditer(body):
            link = m.group(1).strip()
            if link.startswith(SKIP) or "${" in link:
                continue
            target = unquote(link.split("#", 1)[0].split("?", 1)[0])
            if not target:
                continue
            count += 1
            if not (f.parent / target).exists():
                bad += 1
                print(f"{f.relative_to(ROOT)}: 链接失效 -> {link}")
    print(f"检查了 {count} 个相对链接，失效 {bad} 个。")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
