"""牌のクラス（ラベル）の定義と、外部データセットのクラス名の変換。

ラベルはアプリの牌の表記（packages/mahjong_score_engine の Tile）と同じ:
  萬子 1m〜9m / 筒子 1p〜9p / 索子 1s〜9s / 字牌 1z=東 2z=南 3z=西 4z=北 5z=白 6z=發 7z=中
  赤5 5mr / 5pr / 5sr
"""

import re

CLASSES = (
    [f"{n}m" for n in range(1, 10)]
    + [f"{n}p" for n in range(1, 10)]
    + [f"{n}s" for n in range(1, 10)]
    + [f"{n}z" for n in range(1, 8)]
    + ["5mr", "5pr", "5sr"]
)

# FluffyStuff/riichi-mahjong-tiles のファイル名 → ラベル
FLUFFY_FILES = {
    **{f"Man{n}": f"{n}m" for n in range(1, 10)},
    **{f"Pin{n}": f"{n}p" for n in range(1, 10)},
    **{f"Sou{n}": f"{n}s" for n in range(1, 10)},
    "Ton": "1z", "Nan": "2z", "Shaa": "3z", "Pei": "4z",
    "Haku": "5z", "Hatsu": "6z", "Chun": "7z",
    "Man5-Dora": "5mr", "Pin5-Dora": "5pr", "Sou5-Dora": "5sr",
}

_SUIT_WORDS = {
    "m": "m", "man": "m", "manzu": "m", "wan": "m", "character": "m", "characters": "m", "crak": "m", "c": "m",
    "p": "p", "pin": "p", "pinzu": "p", "tong": "p", "dot": "p", "dots": "p", "circle": "p", "circles": "p", "d": "p",
    "s": "s", "sou": "s", "souzu": "s", "so": "s", "tiao": "s", "bamboo": "s", "bam": "s", "b": "s",
}
_HONOR_WORDS = {
    "east": "1z", "ton": "1z", "e": "1z", "dong": "1z",
    "south": "2z", "nan": "2z", "s": "2z",
    "west": "3z", "shaa": "3z", "sha": "3z", "xi": "3z", "w": "3z",
    "north": "4z", "pei": "4z", "pe": "4z", "bei": "4z", "n": "4z",
    "white": "5z", "haku": "5z", "wd": "5z", "whitedragon": "5z", "bai": "5z", "p": "5z",
    "green": "6z", "hatsu": "6z", "gd": "6z", "greendragon": "6z", "fa": "6z", "f": "6z",
    "red": "7z", "chun": "7z", "rd": "7z", "reddragon": "7z", "zhong": "7z", "c": "7z",
}


def normalize_label(name: str):
    """外部データセットのクラス名をラベルに変換する。分からないものは None。

    例: "1m" "m1" "1-man" "Man1" "5mr" "0m" "r5m" "east" "1z" "Ton" "dragon_red"
    """
    raw = name.strip().lower().replace("_", "-").replace(" ", "-")
    compact = raw.replace("-", "")
    if compact in CLASSES:
        return compact
    # 赤5（0m / r5m / 5m-red / aka5m / 5mr）
    m = re.fullmatch(r"(?:0|r5|aka5|red5|5r)([mps])|5([mps])(?:r|red|aka|dora)", compact)
    if m:
        return f"5{m.group(1) or m.group(2)}r"
    m = re.fullmatch(r"([1-9])([a-z]+)|([a-z]+)([1-9])", compact)
    if m:
        num = m.group(1) or m.group(4)
        word = m.group(2) or m.group(3)
        if word in ("z", "ji", "honor", "honour") and 1 <= int(num) <= 7:
            return f"{num}z"
        if word.endswith("dora") or word.endswith("red") or word.endswith("aka"):
            base = re.sub(r"(dora|red|aka)$", "", word)
            if num == "5" and _SUIT_WORDS.get(base):
                return f"5{_SUIT_WORDS[base]}r"
            return None
        suit = _SUIT_WORDS.get(word)
        if suit:
            return f"{num}{suit}"
    # 字牌（east / dragon-red / red-dragon など）
    words = [w for w in raw.split("-") if w and w not in ("wind", "dragon", "tile")]
    joined = "".join(words)
    if joined in _HONOR_WORDS and len(joined) > 1:
        return _HONOR_WORDS[joined]
    if raw.replace("-", "") in ("reddragon", "dragonred"):
        return "7z"
    if raw.replace("-", "") in ("greendragon", "dragongreen"):
        return "6z"
    if raw.replace("-", "") in ("whitedragon", "dragonwhite"):
        return "5z"
    return None
