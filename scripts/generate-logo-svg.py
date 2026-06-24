# Audiowide 폰트로 AUDI·GATE 로고 SVG 생성 (경로 변환)
from __future__ import annotations

import urllib.request
from dataclasses import dataclass
from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

PROJECT_ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = PROJECT_ROOT / "logo" / "fonts"
FONT_PATH = FONT_DIR / "Audiowide-Regular.ttf"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/audiowide/Audiowide-Regular.ttf"

# PNG 원본(360×50) 색상·비율 기준
LIGHT_AUDI_COLOR = "#4F46E5"
LIGHT_GATE_COLOR = "#7C3AED"
LIGHT_DOT_COLOR = "#F59E0B"
DARK_AUDI_COLOR = "#A5B4FC"
DARK_GATE_COLOR = "#FAFAFA"
DARK_DOT_COLOR = "#FBBF24"

BASELINE_Y = 0.78
# AUDI 끝 ~ GATE 시작 사이 간격 (PNG 픽셀 비율 환산)
WORD_GAP = 0.34
DOT_RADIUS = 0.043
VIEW_PADDING = 0.06
LOGO_DISPLAY_WIDTH = 200
LOGO_DISPLAY_HEIGHT = 28


@dataclass
class LogoLayout:
    audi_paths: list[str]
    gate_paths: list[str]
    dot_x: float
    dot_y: float
    content_width: float
    bounds: tuple[float, float, float, float]


def ensure_font() -> Path:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    if not FONT_PATH.exists():
        urllib.request.urlretrieve(FONT_URL, FONT_PATH)
    return FONT_PATH


def draw_glyph(
    glyph_set,
    glyph_name: str,
    pen,
    pen_x: float,
    y_offset: float = BASELINE_Y,
) -> None:
    units_per_em = glyph_set.font["head"].unitsPerEm
    scale = 1.0 / units_per_em
    transform_pen = TransformPen(
        pen,
        Transform().translate(pen_x, y_offset).scale(scale, -scale),
    )
    glyph_set[glyph_name].draw(transform_pen)


def text_to_paths(
    font: TTFont,
    glyph_set,
    text: str,
    x_offset: float = 0.0,
    y_offset: float = BASELINE_Y,
) -> tuple[list[str], float]:
    """텍스트를 SVG path d 문자열 목록과 끝 x 좌표로 변환"""
    paths: list[str] = []
    pen_x = x_offset
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    default_width = hmtx.metrics.get("_default_", (600, 0))[0]

    for char in text:
        glyph_name = cmap.get(ord(char))
        if not glyph_name:
            continue

        advance, _ = hmtx.metrics.get(glyph_name, (default_width, 0))
        pen = SVGPathPen(glyph_set)
        draw_glyph(glyph_set, glyph_name, pen, pen_x, y_offset)

        path_data = pen.getCommands()
        if path_data:
            paths.append(path_data)

        pen_x += advance / font["head"].unitsPerEm

    return paths, pen_x


def measure_bounds(
    font: TTFont,
    glyph_set,
    text: str,
    x_offset: float,
    y_offset: float = BASELINE_Y,
) -> tuple[float, float, float, float]:
    """글자 묶음의 실제 경계 상자 계산"""
    bounds_pen = BoundsPen(glyph_set)
    pen_x = x_offset
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    default_width = hmtx.metrics.get("_default_", (600, 0))[0]

    for char in text:
        glyph_name = cmap.get(ord(char))
        if not glyph_name:
            continue

        advance, _ = hmtx.metrics.get(glyph_name, (default_width, 0))
        draw_glyph(glyph_set, glyph_name, bounds_pen, pen_x, y_offset)
        pen_x += advance / font["head"].unitsPerEm

    if bounds_pen.bounds is None:
        raise RuntimeError(f"글리프 경계를 계산하지 못했습니다: {text}")

    return bounds_pen.bounds


def build_layout(font: TTFont, glyph_set) -> LogoLayout:
    audi_paths, audi_end = text_to_paths(font, glyph_set, "AUDI", 0)
    gate_start = audi_end + WORD_GAP
    gate_paths, total_end = text_to_paths(font, glyph_set, "GATE", gate_start)

    audi_bounds = measure_bounds(font, glyph_set, "AUDI", 0)
    gate_bounds = measure_bounds(font, glyph_set, "GATE", gate_start)

    # 점: AUDI·GATE 사이 중앙, 글자 높이 기준 PNG와 동일 비율(약 58%)
    dot_x = audi_end + WORD_GAP / 2
    text_height = audi_bounds[3] - audi_bounds[1]
    dot_y = audi_bounds[1] + text_height * 0.58

    xmin = min(audi_bounds[0], gate_bounds[0])
    ymin = min(audi_bounds[1], gate_bounds[1], dot_y - DOT_RADIUS)
    xmax = max(audi_bounds[2], gate_bounds[2], total_end)
    ymax = max(audi_bounds[3], gate_bounds[3], dot_y + DOT_RADIUS)

    return LogoLayout(
        audi_paths=audi_paths,
        gate_paths=gate_paths,
        dot_x=dot_x,
        dot_y=dot_y,
        content_width=total_end,
        bounds=(xmin, ymin, xmax, ymax),
    )


def build_logo_svg(
    layout: LogoLayout,
    audi_color: str,
    gate_color: str,
    dot_color: str,
) -> str:
    xmin, ymin, xmax, ymax = layout.bounds
    view_x = xmin - VIEW_PADDING
    view_y = ymin - VIEW_PADDING
    view_width = (xmax - xmin) + VIEW_PADDING * 2
    view_height = (ymax - ymin) + VIEW_PADDING * 2

    audi_elements = "\n  ".join(
        f'<path d="{path_data}" fill="{audi_color}"/>'
        for path_data in layout.audi_paths
    )
    gate_elements = "\n  ".join(
        f'<path d="{path_data}" fill="{gate_color}"/>'
        for path_data in layout.gate_paths
    )

    return f"""<svg width="{LOGO_DISPLAY_WIDTH}" height="{LOGO_DISPLAY_HEIGHT}" viewBox="{view_x:.4f} {view_y:.4f} {view_width:.4f} {view_height:.4f}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="AUDIGATE">
  <title>AUDIGATE</title>
  {audi_elements}
  <circle cx="{layout.dot_x:.4f}" cy="{layout.dot_y:.4f}" r="{DOT_RADIUS:.4f}" fill="{dot_color}"/>
  {gate_elements}
</svg>
"""


def main() -> None:
    font_path = ensure_font()
    font = TTFont(font_path)
    glyph_set = font.getGlyphSet()
    glyph_set.font = font

    layout = build_layout(font, glyph_set)

    themes = [
        ("light.svg", LIGHT_AUDI_COLOR, LIGHT_GATE_COLOR, LIGHT_DOT_COLOR),
        ("dark.svg", DARK_AUDI_COLOR, DARK_GATE_COLOR, DARK_DOT_COLOR),
        ("audigate-wordmark.svg", LIGHT_AUDI_COLOR, LIGHT_GATE_COLOR, LIGHT_DOT_COLOR),
    ]

    for filename, audi_color, gate_color, dot_color in themes:
        svg_content = build_logo_svg(layout, audi_color, gate_color, dot_color)
        output_path = PROJECT_ROOT / "logo" / filename
        output_path.write_text(svg_content, encoding="utf-8")
        print(f"generated: {output_path}")


if __name__ == "__main__":
    main()
