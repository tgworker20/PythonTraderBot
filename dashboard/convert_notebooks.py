# -*- coding: utf-8 -*-
"""تبدیل نوت‌بوک‌های بک‌تست نویسنده به اسکریپت مستقل قابل اجرا
(تا بک‌تست‌های MT5 بدون Jupyter و از داخل اینترفیس اجرا شوند)
این تبدیل از خود نوت‌بوک‌های موجود انجام می‌شود؛ پس با آپدیت‌های بعدی نویسنده هم کار می‌کند."""
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CODE_DIR = REPO_ROOT / "code"

MH_NB = CODE_DIR / "MichaelHarrisSplit.ipynb"
SP2L_NB = CODE_DIR / "SP2L" / "SP2L2_Advanced_Backtest.ipynb"
MH_OUT = CODE_DIR / "run_michael_harris_backtest.py"
SP2L_OUT = CODE_DIR / "SP2L" / "run_sp2l_backtest.py"


def _cells(path):
    nb = json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))
    return ["".join(c.get("source", [])) for c in nb.get("cells", []) if c.get("cell_type") == "code"]


def generate_sp2l_backtest():
    """سلول اولِ نوت‌بوک SP2L (خودکفا) را به اسکریپت مستقل تبدیل می‌کند"""
    if not SP2L_NB.exists():
        return False, "نوت‌بوک SP2L2_Advanced_Backtest.ipynb پیدا نشد."
    cells = _cells(SP2L_NB)
    if not cells:
        return False, "نوت‌بوک سلول کدی ندارد."
    header = (
        "#!/usr/bin/env python\n"
        "# -*- coding: utf-8 -*-\n"
        "# اجرای مستقل بک‌تست SP2L پیشرفته — تولیدشده از SP2L2_Advanced_Backtest.ipynb\n"
        "# نیاز به متاتریدر ۵ (ویندوز) دارد. پارامترها را در بخش SETTINGS ویرایش کنید.\n"
        "__author__ = \"Alireza Sadabadi (converted by Control Center)\"\n\n"
    )
    footer = "\n\nif __name__ == \"__main__\":\n    print()\n    print(\"Backtest finished.\")\n"
    script = header + cells[0] + footer
    SP2L_OUT.write_text(script, encoding="utf-8")
    return True, f"✅ {SP2L_OUT.name} از نوت‌بوک تولید شد."


def generate_michael_harris():
    """ترکیب سلول‌های نوت‌بوک مایکل هریس + اجرای ساده/بهینه‌سازی"""
    if not MH_NB.exists():
        return False, "نوت‌بوک MichaelHarrisSplit.ipynb پیدا نشد."
    cells = _cells(MH_NB)
    if len(cells) < 3:
        return False, "ساختار نوت‌بوک مایکل هریس با انتظار مطابقت ندارد."
    header = (
        "#!/usr/bin/env python\n"
        "# -*- coding: utf-8 -*-\n"
        "# اجرای مستقل بک‌تست استراتژی مایکل هریس — تولیدشده از MichaelHarrisSplit.ipynb\n"
        "# نیاز به متاتریدر ۵ (ویندوز) دارد.\n"
        "# نماد و تعداد کندل را در بخش دریافت داده ویرایش کنید.\n"
        "# بهینه‌سازی SL/TP:  python run_michael_harris_backtest.py --optimize\n"
        "__author__ = \"Alireza Sadabadi (converted by Control Center)\"\n"
        "import sys\n\n"
    )
    data_cell = cells[0]
    signal_cell = cells[1]
    bt_cell = cells[2]
    run_plain = (
        "\n\n# ------------------------- اجرای ساده -------------------------\n"
        "print()\n"
        "print(\"=\" * 50)\n"
        "print(\"RUNNING BACKTEST ...\")\n"
        "print(\"=\" * 50)\n"
        "backtest = Backtest(df, MyStrategy, cash=100, commission=0.0, margin=1/5)\n"
        "result = backtest.run()\n"
        "print(result)\n"
        "trades = result[\"_trades\"]\n"
        "if len(trades) > 0:\n"
        "    wr = 100 * (trades[\"PnL\"] > 0).sum() / len(trades)\n"
        "    print(f\"Win Rate: {wr:.2f}%  |  Trades: {len(trades)}\")\n"
    )
    optimize_cell = (
        "\n\n# ------------------------- بهینه‌سازی (اختیاری) -------------------------\n"
        "if \"--optimize\" in sys.argv:\n"
        "    print()\n"
        "    print(\"=\" * 50)\n"
        "    print(\"RUNNING OPTIMIZATION (slPct x tpPct) ...\")\n"
        "    print(\"=\" * 50)\n"
        "    result, heatmap = backtest.optimize(\n"
        "        slPct=[i / 100 for i in range(1, 10)],\n"
        "        tpPct=[i / 100 for i in range(1, 10)],\n"
        "        maximize=\"Return [%]\", max_tries=3000,\n"
        "        random_state=0, return_heatmap=True)\n"
        "    print(result)\n"
        "    try:\n"
        "        import seaborn as sns\n"
        "        import matplotlib\n"
        "        matplotlib.use(\"Agg\")\n"
        "        import matplotlib.pyplot as plt\n"
        "        plt.figure(figsize=(10, 8))\n"
        "        sns.heatmap(heatmap.unstack(), annot=True, cmap=\"viridis\", fmt=\".0f\")\n"
        "        plt.savefig(\"michael_harris_optimize_heatmap.png\", dpi=110, bbox_inches=\"tight\")\n"
        "        print(\"Heatmap saved: michael_harris_optimize_heatmap.png\")\n"
        "    except Exception as e:\n"
        "        print(\"heatmap skipped:\", e)\n"
        "\n\nif __name__ == \"__main__\":\n"
        "    print()\n"
        "    print(\"Backtest finished.\")\n"
    )
    script = header + data_cell + "\n\n" + signal_cell + "\n\n" + bt_cell + run_plain + optimize_cell
    MH_OUT.write_text(script, encoding="utf-8")
    return True, f"✅ {MH_OUT.name} از نوت‌بوک تولید شد."


def ensure_all():
    """ساخت اسکریپت‌ها فقط اگر موجود نباشند"""
    results = []
    if not SP2L_OUT.exists():
        results.append(generate_sp2l_backtest())
    if not MH_OUT.exists():
        results.append(generate_michael_harris())
    return results
