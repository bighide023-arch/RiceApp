#!/usr/bin/env python3
"""農林水産省の公表データからお米の価格を取得し、data/prices.json を更新する。

取得するデータ:
  retail_weekly    スーパーでの販売価格（KSP-POS、全国、週次、円/5kg税込）
  wholesale_monthly 米の相対取引価格（全銘柄平均と産地品種銘柄別、月次、円/玄米60kg税込）

使い方:
  python3 scripts/fetch_prices.py                     # Webから取得
  python3 scripts/fetch_prices.py --pos-pdf a.pdf --aitai-pdf b.pdf   # 手元のファイルで試す

出典: 農林水産省ウェブサイト（公共データ利用規約 第1.0版）。本スクリプトで加工して作成。
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

POS_PDF_URL = "https://www.maff.go.jp/j/nousan/kokumotu/ksppos.pdf"
AITAI_PAGE_URL = "https://www.maff.go.jp/j/seisan/keikaku/soukatu/aitaikakaku.html"

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "data" / "prices.json"

USER_AGENT = "RiceApp-data-fetcher/0.1"

ZEN = str.maketrans("０１２３４５６７８９，／～〜", "0123456789,/~~")


class ParseError(Exception):
    pass


def http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as res:
        return res.read()


# ---------------------------------------------------------------------------
# 店頭価格（KSP-POS 週次 PDF）
# ---------------------------------------------------------------------------

DATE_RE = re.compile(r"(?:R\d+/)?(\d{1,2})/(\d{1,2})")
PRICE_RE = re.compile(r"(?<![\d/])(\d,\d{3}|\d{4})(?![\d/])")
PUBLISHED_RE = re.compile(r"令和\s*(\d+)\s*年\s*(\d+)\s*月\s*(\d+)\s*日\s*公表")

# 表の行見出し。「その他(ブレンド米等)の販売価格」は見出しが折り返され、値は次の行に出る
ROW_LABELS = {
    "brand": re.compile(r"銘柄米の販売価格"),
    "blend": re.compile(r"その他[(（]ブレンド米"),
    "average": re.compile(r"全平均販売価格"),
}

# 1行にこれ以上の日付・価格が並んでいれば表の行とみなす（本文やグラフの軸ラベルを除くため）
MIN_COLUMNS = 10


def pdf_to_text(pdf_bytes: bytes) -> str:
    with tempfile.NamedTemporaryFile(suffix=".pdf") as f:
        f.write(pdf_bytes)
        f.flush()
        out = subprocess.run(
            ["pdftotext", "-layout", "-enc", "UTF-8", f.name, "-"],
            check=True,
            capture_output=True,
        )
    return out.stdout.decode("utf-8")


def parse_published_date(text: str) -> dt.date:
    m = PUBLISHED_RE.search(text)
    if not m:
        raise ParseError("公表日（令和○年○月○日公表）が見つかりません")
    reiwa, month, day = map(int, m.groups())
    return dt.date(2018 + reiwa, month, day)


def assign_years(periods: list[tuple[int, int, int, int]], published: dt.date) -> list[tuple[dt.date, dt.date]]:
    """年の無い「M/D～M/D」に、公表日から遡って年を付ける。"""
    result: list[tuple[dt.date, dt.date]] = []
    year = published.year
    next_start: dt.date | None = None
    for sm, sd, em, ed in reversed(periods):
        end = dt.date(year, em, ed)
        # 新しい週より後になってしまう（年をまたいだ）場合は前年にする
        while end > published or (next_start and end >= next_start):
            year -= 1
            end = dt.date(year, em, ed)
        start = dt.date(year if (sm, sd) <= (em, ed) else year - 1, sm, sd)
        result.append((start, end))
        next_start = start
        year = start.year
    result.reverse()
    return result


def parse_pos_text(text: str) -> tuple[dt.date, list[dict]]:
    """週次の表を読む。

    pdftotext -layout では、表の見出しが「開始日の行 / ～の行 / 終了日の行」の3行に分かれ、
    前年同期の表と今年の表が上下に並ぶ。
    """
    text = text.translate(ZEN)
    published = parse_published_date(text)

    starts: list[tuple[int, int]] = []
    ends: list[tuple[int, int]] = []
    rows: dict[str, list[int]] = {k: [] for k in ROW_LABELS}
    expect_end = False
    pending: str | None = None

    for line in text.splitlines():
        if line.count("~") >= MIN_COLUMNS:
            expect_end = True
            continue
        dates = DATE_RE.findall(line)
        if len(dates) >= MIN_COLUMNS and not PRICE_RE.search(line):
            (ends if expect_end else starts).extend((int(m), int(d)) for m, d in dates)
            expect_end = False
            continue

        label_end = 0
        for key, label in ROW_LABELS.items():
            m = label.search(line)
            if m:
                pending, label_end = key, m.end()
                break
        if pending is None:
            continue
        prices = [int(p.replace(",", "")) for p in PRICE_RE.findall(line[label_end:])]
        if len(prices) >= MIN_COLUMNS:
            rows[pending].extend(prices)
            pending = None

    if not starts or len(starts) != len(ends):
        raise ParseError(f"週の見出しを読み取れません（開始 {len(starts)} 件 / 終了 {len(ends)} 件）")
    for key, values in rows.items():
        if len(values) != len(starts):
            raise ParseError(f"{key} の値の数 {len(values)} が週の数 {len(starts)} と一致しません")

    periods = [(sm, sd, em, ed) for (sm, sd), (em, ed) in zip(starts, ends)]
    weeks = []
    for i, (start, end) in enumerate(assign_years(periods, published)):
        if (end - start).days != 6:
            raise ParseError(f"週の期間が7日ではありません: {start}〜{end}")
        price = {k: rows[k][i] for k in ROW_LABELS}
        if not all(1000 <= v <= 10000 for v in price.values()):
            raise ParseError(f"{start} の週の価格が想定外です: {price}")
        weeks.append({"week_start": start.isoformat(), "week_end": end.isoformat(), **price})
    return published, weeks


# ---------------------------------------------------------------------------
# 相対取引価格（月次、産地品種銘柄別 PDF）
# ---------------------------------------------------------------------------

CROP_YEAR_RE = re.compile(r"令和\s*(\d+)\s*年産米の相対取引価格")
MONTH_RE = re.compile(r"(\d{1,2})月")
MAX_AITAI_CANDIDATES = 15
VALUE_RE = r"(?:\d{1,3}(?:,\d{3})+|\d+|-|－)"


def find_aitai_pdf_urls(html: str) -> list[str]:
    """一覧ページにある相対取引価格関連の PDF のリンクを、ページ上の順に返す。

    ファイル名の番号は毎月変わり、見出しの位置もページの構成で変わりうるので、
    候補を広めに集めて中身で銘柄別の価格表を探す。
    """
    urls = []
    for u in re.findall(r"""href=["']([^"']*aitaikakaku[^"']*\.pdf)["']""", html, re.I):
        full = urllib.parse.urljoin(AITAI_PAGE_URL, u)
        if full not in urls:
            urls.append(full)
    if not urls:
        n = len(re.findall(r"\.pdf", html, re.I))
        raise ParseError(f"相対取引価格の PDF へのリンクが見つかりません（ページ内の PDF 参照 {n} 件）")
    return urls


def parse_value(v: str) -> int | None:
    return None if v in ("-", "－") else int(v.replace(",", ""))


def parse_aitai_text(text: str) -> dict:
    """銘柄別の相対取引価格表（円/玄米60kg）を読む。"""
    text = text.translate(ZEN)
    m = CROP_YEAR_RE.search(text)
    if not m:
        raise ParseError("「令和○年産米の相対取引価格」の表題が見つかりません")
    crop_year = 2018 + int(m.group(1))

    lines = text.splitlines()
    header = next((ln for ln in lines if len(MONTH_RE.findall(ln)) >= 2 and "品種" not in ln), None)
    if header is None:
        raise ParseError("月の見出し行が見つかりません")
    months: list[str] = []
    year = crop_year
    prev = 0
    for mo in map(int, MONTH_RE.findall(header)):
        if mo < prev:
            year += 1
        months.append(f"{year}-{mo:02d}")
        prev = mo
    n = len(months)

    row_re = re.compile(rf"^\s*(\S+)\s+(\S+)\s+({VALUE_RE}(?:\s+{VALUE_RE}){{{n - 1}}})\s*$")
    avg_re = re.compile(rf"全銘柄平均価格\s+({VALUE_RE}(?:\s+{VALUE_RE}){{{n - 1}}})\s*$")

    brands = []
    average = None
    for ln in lines:
        am = avg_re.search(ln)
        if am:
            average = [parse_value(v) for v in am.group(1).split()]
            continue
        rm = row_re.match(ln)
        if rm:
            values = [parse_value(v) for v in rm.group(3).split()]
            brands.append({
                "region": rm.group(1),
                "variety": rm.group(2),
                "prices": {mo: v for mo, v in zip(months, values) if v is not None},
            })

    if average is None:
        raise ParseError("全銘柄平均価格の行が見つかりません")
    if len(brands) < 50:
        raise ParseError(f"銘柄の行が少なすぎます（{len(brands)} 件）")
    for v in average:
        if v is not None and not 10000 <= v <= 100000:
            raise ParseError(f"全銘柄平均価格が想定外です: {v}")

    return {
        "crop_year": crop_year,
        "average": [{"month": mo, "price": v} for mo, v in zip(months, average) if v is not None],
        "brands": brands,
    }


def fetch_aitai() -> dict:
    """一覧ページの上から順に PDF を開き、銘柄別の価格表として読めた最初のものを返す。"""
    html = http_get(AITAI_PAGE_URL).decode("utf-8", "replace")
    for url in find_aitai_pdf_urls(html)[:MAX_AITAI_CANDIDATES]:
        text = pdf_to_text(http_get(url))
        if "品種銘柄" not in text or "全銘柄平均価格" not in text:
            continue
        try:
            crop = parse_aitai_text(text)
        except ParseError:
            continue
        print(f"相対取引価格の表: {url}")
        return crop
    raise ParseError("銘柄別の相対取引価格の PDF が見つかりません")


# ---------------------------------------------------------------------------

def merge_by_key(old: list[dict], new: list[dict], key: str) -> list[dict]:
    merged = {item[key]: item for item in old}
    merged.update({item[key]: item for item in new})
    return [merged[k] for k in sorted(merged)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pos-pdf", help="KSP-POS の PDF（指定しなければ Web から取得）")
    ap.add_argument("--aitai-pdf", help="相対取引価格（銘柄別）の PDF（指定しなければ Web から取得）")
    ap.add_argument("--dump-text", action="store_true", help="PDF から抽出したテキストを表示して終了")
    ap.add_argument("--out", default=str(OUT_PATH))
    args = ap.parse_args()

    out_path = Path(args.out)
    data = json.loads(out_path.read_text()) if out_path.exists() else {}

    pdf = Path(args.pos_pdf).read_bytes() if args.pos_pdf else http_get(POS_PDF_URL)
    text = pdf_to_text(pdf)
    if args.dump_text:
        print(text)
        return 0
    published, weeks = parse_pos_text(text)
    data["retail_weekly"] = {
        "unit": "円/5kg（税込）",
        "source": "農林水産省「スーパーでの販売数量・価格の推移（KSP-POSデータ全国、週次）」を加工して作成",
        "source_url": POS_PDF_URL,
        "published": published.isoformat(),
        "weeks": merge_by_key(data.get("retail_weekly", {}).get("weeks", []), weeks, "week_start"),
    }

    try:
        if args.aitai_pdf:
            crop = parse_aitai_text(pdf_to_text(Path(args.aitai_pdf).read_bytes()))
        else:
            crop = fetch_aitai()
        old = data.get("wholesale_monthly", {})
        data["wholesale_monthly"] = {
            "unit": "円/玄米60kg（税込）",
            "source": "農林水産省「米の相対取引価格・数量」を加工して作成",
            "source_url": AITAI_PAGE_URL,
            "average": merge_by_key(old.get("average", []), crop["average"], "month"),
            # 銘柄別は最新の産年の表をそのまま持つ
            "crop_year": crop["crop_year"],
            "brands": crop["brands"],
        }
    except (ParseError, OSError, subprocess.CalledProcessError) as e:
        # 相対取引価格が読めなくても、店頭価格の更新は止めない
        print(f"warning: 相対取引価格をスキップ: {e}", file=sys.stderr)

    data["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

    latest = data["retail_weekly"]["weeks"][-1]
    print(f"店頭価格 {latest['week_start']}〜{latest['week_end']}: 全平均 {latest['average']}円/5kg")
    if "wholesale_monthly" in data:
        w = data["wholesale_monthly"]
        print(f"相対取引価格 {w['average'][-1]['month']}: 全銘柄平均 {w['average'][-1]['price']}円/60kg（{len(w['brands'])} 銘柄）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
