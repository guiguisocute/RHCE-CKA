#!/usr/bin/env python3
"""检查仓库内 Markdown / HTML 的相对链接是否有效。

用法：python3 scripts/check-links.py [路径 ...]
默认检查 README.md、index.html、notes/、labs/、journal/、references/README.md。

- 只检查相对链接（不访问网络），忽略 http(s)://、mailto: 等。
- 指向 .md 文件的锚点（file.md#小节 或 #小节）会按 GitHub 的标题锚点规则校验，
  也认 <a id="..."> / <a name="..."> 显式锚点。
"""
import re
import sys
from functools import lru_cache
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ["README.md", "index.html", "notes", "labs", "journal", "references/README.md"]
MD_LINK = re.compile(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HTML_LINK = re.compile(r"""(?:href|src)=["']([^"']+)["']""")
EXPLICIT_ANCHOR = re.compile(r"""<a\s+(?:id|name)=["']([^"']+)["']""")
SKIP = ("http://", "https://", "mailto:", "javascript:", "data:")


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


def slugify(heading):
    """近似 GitHub (github-slugger) 的标题锚点生成规则。"""
    h = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)   # [文字](链接) -> 文字
    h = re.sub(r"<[^>]+>", "", h)                             # 去掉 HTML 标签
    h = h.replace("`", "").replace("*", "").strip().lower()
    h = "".join(ch for ch in h if ch.isalnum() or ch in " -_")
    return h.replace(" ", "-")


@lru_cache(maxsize=None)
def anchors_of(path):
    text = Path(path).read_text(encoding="utf-8")
    found, seen = set(EXPLICIT_ANCHOR.findall(text)), {}
    in_code = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_code = not in_code
            continue
        m = None if in_code else re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if m:
            base = slugify(m.group(2))
            n = seen.get(base, 0)
            found.add(base if n == 0 else f"{base}-{n}")
            seen[base] = n + 1
    return found


def main(argv):
    bad = count = 0
    for f in iter_files(argv):
        text = f.read_text(encoding="utf-8")
        is_html = f.suffix == ".html"
        body = text if is_html else strip_code(text)
        for m in (HTML_LINK if is_html else MD_LINK).finditer(body):
            link = m.group(1).strip()
            if link.startswith(SKIP) or "${" in link:
                continue
            path_part, _, anchor = link.partition("#")
            path_part = unquote(path_part.split("?", 1)[0])
            if is_html and not path_part:
                continue  # 页面内锚点由页面脚本处理
            count += 1
            target = (f.parent / path_part) if path_part else f
            if not target.exists():
                bad += 1
                print(f"{f.relative_to(ROOT)}: 文件不存在 -> {link}")
                continue
            if anchor and target.suffix == ".md" and unquote(anchor).lower() not in anchors_of(str(target.resolve())):
                bad += 1
                print(f"{f.relative_to(ROOT)}: 锚点不存在 -> {link}")
    print(f"检查了 {count} 个相对链接，失效 {bad} 个。")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
