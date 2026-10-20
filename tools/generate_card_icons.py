"""Original SVG symbols, generated reproducibly without raster/third-party art."""

from pathlib import Path

icons = {
    "arcane_shield": '<path d="M32 8 52 16v17c0 12-20 23-20 23S12 45 12 33V16Z"/><path d="M32 18v25m-10-13h20"/>',
    "hidden_snare": '<path d="M32 54V12m0 20L15 18m17 20 18-22M32 47l-19-8m19 8 20-10M21 53l11-6 12 6"/>',
    "frost_bind": '<path d="M32 7v50M10 20l44 24M10 44l44-24M23 12l9 8 9-8M23 52l9-8 9 8"/>',
    "dispel": '<path d="m12 51 35-35m-27 0 6 6m16 16 6 6M9 32h10m26-23v11m1 26h10"/><circle cx="47" cy="16" r="7"/>',
    "shield_break": '<path d="M32 8 52 16v17c0 12-20 23-20 23S12 45 12 33V16Z"/><path d="m36 11-9 18 12 3-12 22"/>',
    "oracle_eye": '<path d="M6 32s12-17 26-17 26 17 26 17-12 17-26 17S6 32 6 32Z"/><circle cx="32" cy="32" r="9"/><circle cx="32" cy="32" r="2"/>',
    "silence_seal": '<circle cx="32" cy="32" r="22"/><path d="m16 16 32 32M26 22h12v20H26Z"/>',
    "arcane_focus": '<path d="m32 6 8 17 18 9-18 8-8 18-8-18-18-8 18-9Z"/><circle cx="32" cy="32" r="7"/>',
    "ward": '<path d="m32 7 23 14v22L32 57 9 43V21Z"/><path d="m20 33 8 8 17-20"/>',
    "trap_disarm": '<path d="m10 51 23-23m-13-7 8 8 15-3 11-13-12 4-7-7 4-6-13 9Z"/><path d="m40 40 14 14m-14 0 14-14"/>',
    "temporal_boost": '<path d="M17 8h30M17 56h30M21 8c0 14 22 18 22 24S21 42 21 56M43 8c0 14-22 18-22 24s22 10 22 24"/>',
    "arcane_draw": '<rect x="12" y="14" width="29" height="40" rx="4"/><path d="M24 14V7h28v39H41m-20-9h13m-6-7v14"/>',
}
destination = Path(__file__).resolve().parents[1] / "client-godot/assets/cards"
destination.mkdir(parents=True, exist_ok=True)
for name, shape in icons.items():
    (destination / f"{name}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#c7a7ff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">{shape}</g></svg>',
        encoding="utf-8",
    )
print("12 original SVG card symbols generated")
