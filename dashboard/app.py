# -*- coding: utf-8 -*-
"""
🎬 PythonTraderBot Control Center
اینترفیس کامل کنترل ربات‌های معاملاتی و بک‌تست‌ها — ساخته‌شده با Streamlit
اجرا:  streamlit run app.py
"""
import sys
from pathlib import Path

import streamlit as st

sys.path.insert(0, str(Path(__file__).resolve().parent))

import catalog
import runner
import engines
import sr_tools
from catalog import BOTS, LIBRARIES, NOTEBOOKS, CLAIMED_STATS
from mt5_utils import MT5_AVAILABLE, mt5_status, fetch_rates, TIMEFRAMES, get_positions_df

# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="مرکز کنترل PythonTraderBot",
    page_icon="🤖",
    layout="wide",
    initial_sidebar_state="expanded",
)

RTL_CSS = """
<style>
@import url('https://fonts.googleapis.com/css2?family=Vazirmatn:wght@400;500;700&display=swap');

html, body, .stApp, [data-testid="stSidebar"] {
    font-family: 'Vazirmatn', 'Segoe UI', Tahoma, sans-serif;
}

/* راست‌چین کردن متن‌ها */
section[data-testid="stSidebar"] *,
.stMarkdown, .stMarkdown *, h1, h2, h3, h4, h5,
[data-testid="stMetricLabel"], [data-testid="stMetricValue"],
.stTabs [data-baseweb="tab"] p {
    direction: rtl;
    text-align: right;
}
section[data-testid="stSidebar"] { direction: rtl; }

/* کد و جدول چپ‌چین بمانند */
code, pre, .stCodeBlock, [data-testid="stDataFrame"], table {
    direction: ltr;
    text-align: left;
}

/* هدر */
.main-header {
    background: linear-gradient(135deg, #1a2980 0%, #26d0ce 100%);
    color: white;
    padding: 1.2rem 1.5rem;
    border-radius: 14px;
    margin-bottom: 1rem;
    text-align: center;
}
.main-header h1 { color: white; margin: 0; font-size: 1.6rem; }
.main-header p { color: #e8f7f7; margin: 0.3rem 0 0 0; font-size: 0.9rem; }

/* کارت آمار */
.stat-card {
    background: #f8fbff;
    border: 1px solid #dbe6f5;
    border-radius: 12px;
    padding: 0.9rem 1rem;
    height: 100%;
}
.stat-card .title { font-size: 0.85rem; color: #5a6b85; margin-bottom: 0.3rem; }
.stat-card .value { font-size: 1.25rem; font-weight: 700; color: #16325c; }
.stat-card .sub { font-size: 0.78rem; color: #7a8aa5; margin-top: 0.25rem; direction: rtl; }

/* وضعیت */
.pill {
    display: inline-block;
    padding: 0.15rem 0.7rem;
    border-radius: 999px;
    font-size: 0.78rem;
    font-weight: 600;
    direction: rtl;
}
.pill-run { background: #d4f8e0; color: #0a7a3d; }
.pill-stop { background: #fde3e1; color: #b3261e; }
.pill-warn { background: #fff4d6; color: #9a6b00; }
.pill-ok { background: #d9f0ff; color: #0b5fa5; }

/* کادر هشدار */
.warn-box {
    background: #fff8e6;
    border-right: 4px solid #e6a700;
    border-radius: 8px;
    padding: 0.7rem 1rem;
    margin: 0.5rem 0;
    font-size: 0.88rem;
    direction: rtl;
}
.info-box {
    background: #eef6ff;
    border-right: 4px solid #2d7dd2;
    border-radius: 8px;
    padding: 0.7rem 1rem;
    margin: 0.5rem 0;
    font-size: 0.88rem;
    direction: rtl;
}
.ok-box {
    background: #edfbf2;
    border-right: 4px solid #1f9d55;
    border-radius: 8px;
    padding: 0.7rem 1rem;
    margin: 0.5rem 0;
    font-size: 0.88rem;
    direction: rtl;
}
.log-box {
    background: #101418;
    color: #c7f0c2;
    font-family: 'Consolas', monospace;
    font-size: 0.75rem;
    border-radius: 8px;
    padding: 0.8rem;
    max-height: 340px;
    overflow: auto;
    direction: ltr;
    text-align: left;
    white-space: pre-wrap;
}
</style>
"""
st.markdown(RTL_CSS, unsafe_allow_html=True)


def header(subtitle):
    st.markdown(
        f"""<div class="main-header">
        <h1>🤖 مرکز کنترل PythonTraderBot</h1>
        <p>{subtitle}</p>
        </div>""",
        unsafe_allow_html=True,
    )


def needs_label(bot):
    labels = []
    m = {
        "mt5": "متاتریدر۵",
        "sr_csv": "فایل سطوح S/R",
        "pandas_ta": "pandas-ta",
        "internet": "اینترنت",
        "torch": "PyTorch",
    }
    for n in bot.get("needs", []):
        labels.append(m.get(n, n))
    return "، ".join(labels) if labels else "—"


def _fmt(v):
    if isinstance(v, float):
        return f"{v:,.4f}".rstrip("0").rstrip(".")
    return v


def pd_series_fa(d):
    import pandas as pd
    return pd.DataFrame({"مقدار": [_fmt(v) for v in d.values()]}, index=list(d.keys()))


# ---------------------------------------------------------------------------
# نوار کناری
# ---------------------------------------------------------------------------
st.sidebar.markdown("## 🎛️ مرکز کنترل")
page = st.sidebar.radio(
    "صفحه",
    [
        "🏠 داشبورد",
        "🤖 ربات‌های زنده",
        "📈 بک‌تست",
        "📊 آمار و وین‌ریت‌ها",
        "🧰 ابزارها",
        "⬇️ دانلود پکیج",
        "📖 راهنما",
    ],
    label_visibility="collapsed",
)
st.sidebar.markdown("---")

# وضعیت متاتریدر در سایدبار
status = mt5_status()
if status["available"] and status.get("initialized"):
    acc = status.get("account") or {}
    st.sidebar.success(f"✅ متاتریدر متصل — {acc.get('login', '?')} @ {acc.get('server', '?')}")
    st.sidebar.caption(
        f"موجودی: {acc.get('balance', 0):,.2f} {acc.get('currency', '')} | "
        f"اکوییتی: {acc.get('equity', 0):,.2f} | لوریج: 1:{acc.get('leverage', '?')}"
    )
    if status.get("open_positions"):
        st.sidebar.caption(f"📌 پوزیشن باز: {status['open_positions']}")
elif status["available"]:
    st.sidebar.warning("⚠️ متاتریدر نصب است اما اتصال برقرار نشد")
    st.sidebar.caption("ترمینال MetaTrader 5 را باز کنید و وارد حساب شوید.")
else:
    st.sidebar.warning("⚠️ متاتریدر در دسترس نیست")
    st.sidebar.caption("ربات‌های MT5 فقط روی ویندوز با ترمینال باز کار می‌کنند. بک‌تست‌های yfinance و CSV همین‌جا کار می‌کنند.")

st.sidebar.markdown("---")
running = runner.running_bots()
st.sidebar.markdown(
    f"**ربات‌های فعال:** {len(running)}"
)
if running:
    for bid in running:
        bot = catalog.get_bot(bid)
        st.sidebar.markdown(f"&nbsp;&nbsp;🟢 {bot['name'] if bot else bid}")
st.sidebar.caption("ساخته‌شده برای ریپازیتوری Alireza Sadabadi")

# ===========================================================================
# صفحه: داشبورد
# ===========================================================================
if page == "🏠 داشبورد":
    header("نمای کلی مجموعهٔ ربات‌های معاملاتی")

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("🤖 ربات‌های لایو", len([b for b in BOTS if b["category"] == "ربات لایو"]))
    c2.metric("📈 بک‌تست‌های داخلی", len([n for n in NOTEBOOKS if n.get("builtin")]))
    c3.metric("📚 نوت‌بوک تحلیلی", len(NOTEBOOKS))
    c4.metric("⚙️ کتابخانه‌های هسته", len(LIBRARIES))

    st.markdown("### 🏆 آمارهای اعلام‌شدهٔ نویسنده (از README ریپازیتوری)")
    st.markdown(
        """<div class="info-box">این اعداد <b>ادعای نویسنده</b> هستند؛ صحت هر کدام را می‌توانید با
        صفحهٔ «📈 بک‌تست» روی دادهٔ دلخواه خودتان بسنجید.</div>""",
        unsafe_allow_html=True,
    )
    cards = [
        ("TraderBot", "84%", "سود در ۱۰ روز"),
        ("SP2L_Advanced", "84%", "وین‌ریت | PF=5.5 | بازده 43%"),
        ("LeverageLongRun", "85%", "وین‌ریت | سود 1700%"),
        ("VWAP_BB_RSI", "62%", "وین‌ریت"),
        ("CE_ZLSMA_HA_ATR", "1700%", "سود ادعاشده"),
        ("MichaelHarrisSplit", "370%", "سود گزارش‌شده"),
    ]
    cols = st.columns(3)
    for i, (name, val, sub) in enumerate(cards):
        with cols[i % 3]:
            st.markdown(
                f"""<div class="stat-card">
                <div class="title">{name}</div>
                <div class="value">{val}</div>
                <div class="sub">{sub}</div>
                </div>""",
                unsafe_allow_html=True,
            )

    st.markdown("### 📂 نقشهٔ مجموعه")
    tree = """
```
PythonTraderBot/
├── code/                     ← کد اصلی ربات‌ها
│   ├── Meta.py               ← لایهٔ اجرای متاتریدر (کپی برای اجرای مستقیم)
│   ├── TelegramBot.py        ← اعلان‌های تلگرام
│   ├── EasyBot.py / TraderBot.py / BB_Full.py / BB_Half.py
│   ├── CE_ZLSMA_HA.py / CE_ZLSMA_HA_ATR.py
│   ├── HA_RSI_CE_EMA_Scalper.py / VWAP_BB_RSI.py
│   ├── TrailingBot.py / SMABestPerformance.py / get.py
│   ├── CoinexApi.py          ← لایهٔ صرافی CoinEx
│   ├── run_michael_harris_backtest.py   ← بک‌تست آماده (MT5)
│   ├── SP2L/                 ← استراتژی پورصمدی + بک‌تست آماده (MT5)
│   ├── SupportResistance/    ← تشخیص سطوح حمایت/مقاومت
│   ├── NewsSentimentClassifier/  ← تحلیل احساسات اخبار
│   └── *.ipynb               ← نوت‌بوک‌های ML و تحلیل
└── dashboard/                ← همین اینترفیس (Streamlit)
```
"""
    st.markdown(tree)

# ===========================================================================
# صفحه: ربات‌های زنده
# ===========================================================================
elif page == "🤖 ربات‌های زنده":
    header("اجرای زندهٔ ربات‌ها — کنترل کامل: اجرا، توقف، لاگ زنده")

    if not MT5_AVAILABLE:
        st.markdown(
            """<div class="warn-box">⚠️ <b>پکیج MetaTrader5 روی این سیستم موجود نیست.</b>
            ربات‌هایی که برچسب «متاتریدر۵» دارند روی این محیط اجرا نمی‌شوند — پکیج MetaTrader5 فقط در
            <b>ویندوز</b> (با ترمینال متاتریدر باز و لاگین‌شده) کار می‌کند. روی سیستم ویندوزی خودتان
            (پکیج دانلودی) همهٔ ربات‌ها از همین صفحه قابل اجرا هستند. ربات تحلیل اخبار بدون متاتریدر همین‌جا قابل اجراست.</div>""",
            unsafe_allow_html=True,
        )
    else:
        if status.get("initialized"):
            acc = status.get("account") or {}
            st.markdown(
                f"""<div class="ok-box">✅ متصل به حساب <b>{acc.get('login')}</b> روی سرور
                <b>{acc.get('server')}</b> — موجودی {acc.get('balance', 0):,.2f} — پوزیشن باز: {status.get('open_positions', 0)}</div>""",
                unsafe_allow_html=True,
            )
        else:
            st.markdown(
                """<div class="warn-box">⚠️ متاتریدر نصب است اما اتصال برقرار نشد؛ ترمینال را باز کنید و دوباره صفحه را بروزرسانی کنید.</div>""",
                unsafe_allow_html=True,
            )

    auto_refresh = st.toggle("🔄 بروزرسانی خودکار وضعیت و لاگ (هر ۵ ثانیه)", value=False)
    st.markdown("---")

    # فیلتر
    categories = ["همه"] + sorted(set(b["category"] for b in BOTS))
    fcol1, fcol2 = st.columns([3, 1])
    with fcol2:
        cat_filter = st.selectbox("دسته‌بندی", categories)

    for bot in BOTS:
        if cat_filter != "همه" and bot["category"] != cat_filter:
            continue
        run = runner.is_running(bot["id"])
        pinfo = runner.process_info(bot["id"])
        state_html = (
            f'<span class="pill pill-run">🟢 در حال اجرا (PID {pinfo["pid"]})</span>' if run
            else ('<span class="pill pill-stop">⚪ متوقف' + (
                f' — کد خروج {pinfo["returncode"]}' if pinfo.get("returncode") not in (None,) else '') + '</span>'
            )
        )
        claim_html = ""
        if bot.get("claimed"):
            c = bot["claimed"]
            claim_html = f'<span class="pill pill-ok">🏆 {c["metric"]}: {c["value"]}</span>'

        with st.expander(f"{'🟢' if run else '⚙️'} {bot['name']} — {state_html} &nbsp; {claim_html}", expanded=run):
            m1, m2, m3, m4 = st.columns(4)
            m1.markdown(f"**فایل:** `{bot['folder'] + '/' if bot['folder'] else ''}{bot['file']}`")
            m2.markdown(f"**تایم‌فریم:** {bot['timeframe']}")
            m3.markdown(f"**Magic:** {bot['magic']}")
            m4.markdown(f"**نماد:** {bot['symbol']}")
            st.markdown(f"**استراتژی:** {bot['strategy']}")
            st.markdown(f"**توضیح:** {bot['desc']}")
            st.markdown(f"**پیش‌نیازها:** {needs_label(bot)}")
            if bot.get("warning"):
                st.markdown(f'<div class="warn-box">⚠️ {bot["warning"]}</div>', unsafe_allow_html=True)

            bc1, bc2, bc3, _ = st.columns([1, 1, 1, 2])
            if run:
                if bc1.button(f"⛔ توقف {bot['name']}", key=f"stop_{bot['id']}", type="primary"):
                    ok, msg = runner.stop_bot(bot["id"])
                    st.toast(msg)
                    st.rerun()
            else:
                can_run = True
                if "mt5" in bot.get("needs", []) and not MT5_AVAILABLE:
                    can_run = False
                if bc1.button(f"▶️ اجرای {bot['name']}", key=f"start_{bot['id']}",
                              type="primary", disabled=not can_run):
                    ok, msg = runner.start_bot(bot["id"])
                    st.toast(msg)
                    st.rerun()
            if bc2.button("🔄 بروزرسانی لاگ", key=f"refresh_{bot['id']}"):
                st.rerun()
            if bc3.button("🧹 پاک‌کردن لاگ", key=f"clear_{bot['id']}"):
                try:
                    runner.log_path(bot["id"]).unlink(missing_ok=True)
                    st.rerun()
                except OSError:
                    pass
            st.markdown(f"**لاگ زنده:**")
            st.markdown(f'<div class="log-box">{runner.read_log(bot["id"], tail=60)}</div>',
                        unsafe_allow_html=True)

    st.markdown("---")
    st.markdown("### 🛑 کنترل کلی")
    if st.button("⛔ توقف همهٔ ربات‌های در حال اجرا", type="primary", width='stretch'):
        stopped = runner.stop_all()
        st.toast(f"{len(stopped)} ربات متوقف شد.")
        st.rerun()

    if auto_refresh:
        import time as _t
        _t.sleep(5)
        st.rerun()

# ===========================================================================
# صفحه: بک‌تست
# ===========================================================================
elif page == "📈 بک‌تست":
    header("اجرای بک‌تست‌ها روی دادهٔ واقعی یا فایل دلخواه")
    st.markdown(
        """<div class="info-box">💡 چهار بک‌تست اول <b>داخل همین اینترفیس</b> اجرا می‌شوند (نیازی به Jupyter نیست).
        دو مورد آخر به متاتریدر نیاز دارند و به‌صورت اسکریپت مستقل اجرا می‌شوند.</div>""",
        unsafe_allow_html=True,
    )
    tabs = st.tabs([
        "🔗 زنجیرهٔ مارکوف",
        "💰 لوریج SPY→UPRO",
        "⚡ اسکالپر HA_RSI",
        "📊 بهینه‌ساز SMA",
        "🏅 مایکل هریس (MT5)",
        "🥇 SP2L پیشرفته (MT5)",
    ])

    # ------------------------------------------------------------------ مارکوف
    with tabs[0]:
        st.markdown("#### بک‌تست زنجیرهٔ مارکوف روی سهام آمریکا")
        st.caption("پورت‌شده از Markov.ipynb — بعد از n کندل هم‌رنگ پشت‌سرهم، معاملهٔ معکوس باز می‌شود.")
        mk_src = st.radio("منبع داده", ["دانلود از یاهو فایننس (yfinance)", "آپلود فایل CSV (هر نماد، جداگانه)"],
                          horizontal=True, key="mk_src")
        mk_data = None
        if mk_src.startswith("آپلود"):
            mk_files = st.file_uploader("فایل‌های CSV کندل — نام فایل = نام نماد (مثلاً AAPL.csv)",
                                        type=["csv"], accept_multiple_files=True, key="mk_files")
            if mk_files:
                import pandas as pd
                mk_data = {}
                for f in mk_files:
                    try:
                        name = Path(f.name).stem.upper()
                        mk_data[name] = sr_tools.normalize_candles(pd.read_csv(f))
                    except Exception as e:
                        st.error(f"خطا در {f.name}: {e}")
                if mk_data:
                    st.success(f"✅ {len(mk_data)} نماد بارگذاری شد: {', '.join(mk_data.keys())}")
        c1, c2 = st.columns(2)
        with c1:
            tickers_str = st.text_area(
                "نمادها (با کاما جدا کنید)",
                "GOOGL, AMZN, META, AAPL, MSFT, TSLA, NVDA, CEG, JNJ, V,\nSPY, QQQ, DIA, IWM, ARKK, DG, XLK, XLV, XLY, CRWV",
                height=110, key="mk_tickers",
                disabled=mk_data is not None)
            d1, d2 = st.columns(2)
            start_date = d1.text_input("تاریخ شروع", "2015-01-01", key="mk_start", disabled=mk_data is not None)
            end_date = d2.text_input("تاریخ پایان", "2025-06-04", key="mk_end", disabled=mk_data is not None)
        with c2:
            n_candles = st.slider("تعداد کندل هم‌رنگ (n)", 1, 10, 2, key="mk_n")
            mode = st.radio("حالت استراتژی", ["خرید+فروش", "فقط خرید"], key="mk_mode")
            cash = st.number_input("سرمایه اولیه هر نماد [$]", 100, 1_000_000, 1000, 100, key="mk_cash")
            commission = st.number_input("کارمزد", 0.0, 0.01, 0.0002, 0.0001, format="%.4f", key="mk_comm")

        if st.button("🚀 اجرای بک‌تست مارکوف", type="primary", key="mk_run"):
            if mk_data is not None:
                tickers = list(mk_data.keys())
            else:
                tickers = [t.strip().upper() for t in tickers_str.replace("\n", ",").split(",") if t.strip()]
            if not tickers:
                st.error("حداقل یک نماد وارد کنید.")
            else:
                with st.spinner(f"اجرای بک‌تست روی {len(tickers)} نماد..."):
                    try:
                        res = engines.run_markov_backtest(
                            tickers, start_date, end_date, n=int(n_candles),
                            cash=float(cash), commission=float(commission),
                            mode="buy+sell" if mode == "خرید+فروش" else "buy",
                            data_by_ticker=mk_data)
                        st.session_state["mk_result"] = res
                    except Exception as e:
                        st.error(f"خطا: {e}")
                        st.caption("اگر سرور شما به یاهو فایننس دسترسی ندارد، از گزینهٔ آپلود CSV استفاده کنید.")

        if "mk_result" in st.session_state:
            res = st.session_state["mk_result"]
            st.markdown("##### 📐 معیار آماری الگوها")
            m1, m2 = st.columns(2)
            items = list(res["metrics"].items())
            for i, (k, v) in enumerate(items):
                if isinstance(v, float):
                    (m1 if i % 2 == 0 else m2).metric(k, f"{v * 100:.1f}%")
                else:
                    (m1 if i % 2 == 0 else m2).metric(k, f"{v:,}")
            st.markdown("##### 📋 نتایج به تفکیک نماد")
            st.dataframe(res["results"].style.format(precision=2), width='stretch')
            agg = res["aggregate"]
            if agg:
                st.markdown("##### 📊 نتایج تجمیعی")
                a1, a2, a3 = st.columns(3)
                a1.metric("مجموع بازده", f"{agg['مجموع بازده [%]']:.1f}%")
                a2.metric("میانگین بازده", f"{agg['میانگین بازده [%]']:.1f}%")
                a3.metric("میانگین وین‌ریت", f"{agg['میانگین وین‌ریت [%]']:.1f}%")
            st.bar_chart(res["results"].set_index("نماد")["بازده [%]"])

    # ------------------------------------------------------------- لوریج SPY/UPRO
    with tabs[1]:
        st.markdown("#### بک‌تست Leverage for the Long Run (سیگنال از SPY، معامله روی UPRO)")
        st.caption("پورت‌شده از LeverageLongRun_SPY_UPRO.ipynb — بر پایهٔ مقالهٔ برندهٔ جایزهٔ Charles H. Dow در ۲۰۱۶.")
        st.markdown('<div class="ok-box">🏆 ادعای نویسنده: وین‌ریت ۸۵٪ و سود ۱۷۰۰٪ — همین‌جا روی دادهٔ دلخواه تستش کنید.</div>', unsafe_allow_html=True)
        lg_src = st.radio("منبع داده", ["دانلود از یاهو فایننس (yfinance)", "آپلود دو فایل CSV (پایه و لوریج‌دار)"],
                          horizontal=True, key="lg_src")
        lg_data = None
        if lg_src.startswith("آپلود"):
            lf1, lf2 = st.columns(2)
            up_base = lf1.file_uploader("CSV نماد پایه (مثل SPY)", type=["csv"], key="lg_base_file")
            up_lev = lf2.file_uploader("CSV نماد لوریج‌دار (مثل UPRO)", type=["csv"], key="lg_lev_file")
            if up_base and up_lev:
                import pandas as pd
                try:
                    lg_data = {
                        "BASE": sr_tools.normalize_candles(pd.read_csv(up_base)),
                        "LEV": sr_tools.normalize_candles(pd.read_csv(up_lev)),
                    }
                    st.success("✅ هر دو فایل بارگذاری شد.")
                except Exception as e:
                    st.error(f"خطا: {e}")
        c1, c2 = st.columns(2)
        with c1:
            base_t = st.text_input("نماد پایه (کم‌نوسان)", "SPY", key="lg_base", disabled=lg_data is not None)
            lev_t = st.text_input("نماد لوریج‌دار (×3)", "UPRO", key="lg_lev", disabled=lg_data is not None)
            d1, d2 = st.columns(2)
            lg_start = d1.text_input("شروع", "2023-01-01", key="lg_start", disabled=lg_data is not None)
            lg_end = d2.text_input("پایان", "2025-07-28", key="lg_end", disabled=lg_data is not None)
        with c2:
            sma_len = st.slider("طول SMA", 10, 300, 100, key="lg_sma")
            cash2 = st.number_input("سرمایه اولیه [$]", 1000, 10_000_000, 100000, 1000, key="lg_cash")
            comm2 = st.number_input("کارمزد", 0.0, 0.01, 0.0002, 0.0001, format="%.4f", key="lg_comm")

        if st.button("🚀 اجرای بک‌تست لوریج", type="primary", key="lg_run"):
            with st.spinner("اجرای بک‌تست..."):
                try:
                    if lg_data is not None:
                        base_key, lev_key = "BASE", "LEV"
                    else:
                        base_key, lev_key = base_t.strip().upper(), lev_t.strip().upper()
                    res = engines.run_leverage_backtest(
                        base_key, lev_key,
                        lg_start, lg_end, sma_length=int(sma_len),
                        cash=float(cash2), commission=float(comm2),
                        data_by_ticker=lg_data)
                    st.session_state["lg_result"] = res
                except Exception as e:
                    st.error(f"خطا: {e}")
                    st.caption("اگر سرور شما به یاهو فایننس دسترسی ندارد، از گزینهٔ آپلود CSV استفاده کنید.")

        if "lg_result" in st.session_state:
            res = st.session_state["lg_result"]
            stats = res["stats"]
            s = engines.stats_summary(stats)
            st.markdown("##### 📊 خلاصهٔ نتایج")
            k1, k2, k3, k4 = st.columns(4)
            k1.metric("بازده کل", f"{s['بازده کل [%]']:.1f}%")
            k2.metric("وین‌ریت", f"{s['وین‌ریت [%]']:.1f}%")
            k3.metric("تعداد معامله", s["تعداد معاملات"])
            k4.metric("حداکثر افت", f"{s['حداکثر افت سرمایه [%]']:.1f}%")
            st.markdown("##### 📈 منحنی سرمایه")
            ec = engines.equity_curve(stats)
            st.line_chart(ec["Equity"])
            st.markdown("##### 📉 دراودان")
            st.line_chart(ec["Drawdown %"])
            st.markdown("##### 📋 جزئیات کامل")
            st.dataframe(pd_series_fa(engines.stats_summary(stats)), width='stretch')
            st.markdown("##### 🧾 معاملات")
            tt = engines.trades_table(stats)
            if not tt.empty:
                st.dataframe(tt, width='stretch')
            else:
                st.info("معامله‌ای انجام نشد — پارامترها (تاریخ‌ها/طول SMA) را تغییر دهید.")

    # ------------------------------------------------------------------ اسکالپر
    with tabs[2]:
        st.markdown("#### بک‌تست ربات اسکالپر HA_RSI_CE_EMA (تایم M1)")
        st.caption("پورت‌شده از HA_RSI_CE_EMA_Scalper_Backtesting.ipynb — هیکن‌آشی روی RSI + شندلر اکیت + فیلتر EMA200.")
        st.markdown(
            """<div class="info-box">📥 دادهٔ کندل M1 را از فایل CSV آپلود کنید (خروجی متاتریدر یا هر منبع دیگر).
            ستون‌های لازم: time, open, high, low, close (+ حجم اختیاری).
            می‌توانید از صفحهٔ «🧰 ابزارها» هم اگر متاتریدر وصل باشد، مستقیم داده بگیرید و خروجی CSV ذخیره کنید.</div>""",
            unsafe_allow_html=True,
        )
        up = st.file_uploader("آپلود فایل کندل (CSV)", type=["csv"], key="sc_file")
        c1, c2 = st.columns(2)
        with c1:
            sc_cash = st.number_input("سرمایه اولیه [$]", 1000, 10_000_000, 110000, 1000, key="sc_cash")
            sc_size = st.number_input("حجم هر معامله (lot)", 0.001, 1.0, 0.01, 0.001, key="sc_size")
            sc_risk = st.number_input("ریسک (کسری از سرمایه)", 0.01, 0.5, 0.06, 0.01, key="sc_risk")
            sc_reward = st.number_input("حد سود (نسبت)", 0.01, 1.0, 0.12, 0.01, key="sc_reward")
        with c2:
            sc_upper = st.number_input("سطح RSI خروج خرید", 50, 95, 66, key="sc_upper")
            sc_lower = st.number_input("سطح RSI خروج فروش", 5, 50, 28, key="sc_lower")
            sc_leverage = st.number_input("لوریج", 1, 500, 100, key="sc_lev")

        if st.button("🚀 اجرای بک‌تست اسکالپر", type="primary", key="sc_run"):
            if up is None:
                st.warning("اول فایل CSV کندل‌ها را آپلود کنید.")
            else:
                with st.spinner("پردازش سیگنال و اجرای بک‌تست..."):
                    try:
                        import pandas as pd
                        df = pd.read_csv(up)
                        df = sr_tools.normalize_candles(df)
                        res = engines.run_scalper_backtest(
                            df, cash=float(sc_cash), size=float(sc_size),
                            risk_pct=float(sc_risk), reward_pct=float(sc_reward),
                            leverage=float(sc_leverage),
                            upper=float(sc_upper), lower=float(sc_lower))
                        st.session_state["sc_result"] = res
                    except Exception as e:
                        st.error(f"خطا: {e}")

        if "sc_result" in st.session_state:
            res = st.session_state["sc_result"]
            stats = res["stats"]
            if res.get("size_note"):
                st.markdown(f'<div class="warn-box">{res["size_note"]}</div>', unsafe_allow_html=True)
            s = engines.stats_summary(stats)
            st.markdown("##### 📊 خلاصهٔ نتایج")
            k1, k2, k3, k4 = st.columns(4)
            k1.metric("بازده کل", f"{s['بازده کل [%]']:.1f}%")
            k2.metric("وین‌ریت", f"{s['وین‌ریت [%]']:.1f}%")
            k3.metric("تعداد معامله", s["تعداد معاملات"])
            k4.metric("حداکثر افت", f"{s['حداکثر افت سرمایه [%]']:.1f}%")
            st.markdown("##### 📈 منحنی سرمایه")
            st.line_chart(engines.equity_curve(stats)["Equity"])
            st.markdown("##### 📋 جزئیات کامل")
            st.dataframe(pd_series_fa(s), width='stretch')
            tt = engines.trades_table(stats)
            if not tt.empty:
                st.markdown("##### 🧾 معاملات (۲۰۰ مورد آخر)")
                st.dataframe(tt, width='stretch')
            else:
                st.info("معامله‌ای انجام نشد — پارامترها را تغییر دهید یا دادهٔ بیشتری بدهید.")

    # --------------------------------------------------------------- بهینه‌ساز SMA
    with tabs[3]:
        st.markdown("#### بهینه‌ساز پارامترهای SMA (گریدسرچ وکتوری)")
        st.caption("پورت‌شده از SMABestPerformance.py — کل ترکیب‌های SMA سریع/کند را می‌سنجد و بهترین‌ها را می‌دهد.")
        up2 = st.file_uploader("آپلود فایل کندل (CSV) — مثل BitcoinH4.csv", type=["csv"], key="sm_file")
        c1, c2 = st.columns(2)
        with c1:
            sm_fast = st.slider("حداکثر طول SMA سریع", 5, 300, 60, key="sm_fast")
            sm_slow = st.slider("حداکثر طول SMA کند", 5, 300, 60, key="sm_slow")
        with c2:
            st.caption("⚠️ محدوده‌های بزرگ = زمان بیشتر. ۶۰×۶۰ یعنی ۳۶۰۰ ترکیب (چند ثانیه). ۳۰۰×۳۰۰ = ۹۰هزار ترکیب (چند دقیقه).")

        if st.button("🚀 اجرای بهینه‌سازی", type="primary", key="sm_run"):
            if up2 is None:
                st.warning("اول فایل CSV کندل‌ها را آپلود کنید.")
            else:
                import pandas as pd
                try:
                    df = pd.read_csv(up2)
                    df = sr_tools.normalize_candles(df)
                except Exception as e:
                    st.error(f"خطا در خواندن فایل: {e}")
                else:
                    total = sm_fast * sm_slow
                    prog = st.progress(0.0, text="در حال محاسبه...")
                    try:
                        out = engines.run_sma_optimizer(
                            df, fast_max=sm_fast, slow_max=sm_slow,
                            progress_cb=lambda p: prog.progress(min(p, 1.0), text=f"پیشرفت: {p * 100:.0f}%"))
                        prog.empty()
                        st.session_state["sm_result"] = out
                    except Exception as e:
                        prog.empty()
                        st.error(f"خطا: {e}")

        if "sm_result" in st.session_state:
            out = st.session_state["sm_result"]
            best = out.iloc[0]
            st.markdown("##### 🏆 بهترین ترکیب")
            b1, b2, b3 = st.columns(3)
            b1.metric("SMA سریع", int(best["SMA_FAST"]))
            b2.metric("SMA کند", int(best["SMA_SLOW"]))
            b3.metric("بازده تجمعی", f"{best['performance']:.2f}×")
            st.markdown("##### 📋 ۱۰ ترکیب برتر")
            st.dataframe(out.head(10).reset_index(drop=True), width='stretch')
            st.markdown("##### 📋 ۵ ترکیب بد")
            st.dataframe(out.tail(5).reset_index(drop=True), width='stretch')
            csv_data = out.to_csv(index=False).encode("utf-8")
            st.download_button("⬇️ دانلود کل نتایج", csv_data, "sma_optimization_results.csv", "text/csv")

    # ------------------------------------------------------------ مایکل هریس MT5
    with tabs[4]:
        st.markdown("#### بک‌تست استراتژی مایکل هریس (نیازمند متاتریدر)")
        st.caption("تبدیل‌شده از MichaelHarrisSplit.ipynb — سود گزارش‌شده: ۳۷۰٪. داده را مستقیم از متاتریدر می‌گیرد (CARDANO/H4).")
        if not MT5_AVAILABLE:
            st.markdown(
                """<div class="warn-box">⚠️ این بک‌تست به پکیج MetaTrader5 نیاز دارد که فقط روی ویندوز نصب می‌شود.
                روی سیستم ویندوزی خودتان (پکیج دانلودی) از همین صفحه اجرا کنید.</div>""",
                unsafe_allow_html=True,
        )
        else:
            if st.button("🚀 اجرای بک‌تست مایکل هریس", type="primary", key="mh_run"):
                ok, msg = runner.start_bot("__mh_bt")
                st.toast(msg)
            info = runner.process_info("__mh_bt")
            if info["state"] != "stopped":
                if st.button("⛔ توقف", key="mh_stop"):
                    runner.stop_bot("__mh_bt")
                    st.rerun()
            st.markdown("**لاگ:**")
            st.markdown(f'<div class="log-box">{runner.read_log("__mh_bt", tail=100)}</div>', unsafe_allow_html=True)
            st.caption("برای تغییر نماد/تعداد کندل، فایل code/run_michael_harris_backtest.py را ویرایش کنید (بخش DATA).")

    # ----------------------------------------------------------------- SP2L MT5
    with tabs[5]:
        st.markdown("#### بک‌تست SP2L پیشرفته — موتور شبیه‌سازی دست‌نویس (نیازمند متاتریدر)")
        st.caption("تبدیل‌شده از SP2L2_Advanced_Backtest.ipynb (~۲۵۰۰ خط) — شبیه‌سازی کامل استراتژی طلا XAUUSD/M1 با win_rate، profit_factor و max_drawdown.")
        st.markdown('<div class="ok-box">🏆 ادعای نویسنده: وین‌ریت ۸۴٪ | پروفیت‌فاکتور 5.5 | بازده ۴۳٪</div>', unsafe_allow_html=True)
        if not MT5_AVAILABLE:
            st.markdown(
                """<div class="warn-box">⚠️ این بک‌تست به پکیج MetaTrader5 نیاز دارد که فقط روی ویندوز نصب می‌شود.
                روی سیستم ویندوزی خودتان (پکیج دانلودی) از همین صفحه اجرا کنید.</div>""",
                unsafe_allow_html=True,
        )
        else:
            if st.button("🚀 اجرای بک‌تست SP2L", type="primary", key="sp_run"):
                ok, msg = runner.start_bot("__sp_bt")
                st.toast(msg)
            info = runner.process_info("__sp_bt")
            if info["state"] != "stopped":
                if st.button("⛔ توقف", key="sp_stop"):
                    runner.stop_bot("__sp_bt")
                    st.rerun()
            st.markdown("**لاگ:**")
            st.markdown(f'<div class="log-box">{runner.read_log("__sp_bt", tail=120)}</div>', unsafe_allow_html=True)
            st.caption("پارامترها (فیلترها، TP_R، ورود دوم و...) در ابتدای فایل code/SP2L/run_sp2l_backtest.py قابل تغییرند.")


# ===========================================================================
# صفحه: آمار و وین‌ریت‌ها
# ===========================================================================
elif page == "📊 آمار و وین‌ریت‌ها":
    header("آمارهای عملکرد اعلام‌شدهٔ نویسنده برای هر ربات")

    st.markdown(
        """<div class="info-box">📌 منبع این جدول <b>code/README.md</b> ریپازیتوری است؛ این‌ها
        <b>ادعاهای نویسنده</b> هستند (معمولاً روی بک‌تست/دورهٔ خاصی از بازار). برای اعتبارسنجی هر عدد،
        به صفحهٔ «📈 بک‌تست» بروید و همان استراتژی را روی دادهٔ خودتان اجرا کنید.</div>""",
        unsafe_allow_html=True,
    )

    rows = []
    bot_map = {b["name"].split(" (")[0]: b for b in BOTS}
    for key, c in CLAIMED_STATS.items():
        rows.append({
            "ربات/استراتژی": key,
            "معیار": c["metric"],
            "مقدار اعلام‌شده": c["value"],
            "متن اصلی README": c["raw"],
        })
    rows.append({
        "ربات/استراتژی": "SP2L_Bot (آموزشی)",
        "معیار": "—",
        "مقدار اعلام‌شده": "عدد مستقلی اعلام نشده (نسخهٔ آموزشی استراتژی)",
        "متن اصلی README": "It has simpler code for learning",
    })
    st.dataframe(rows, width='stretch', hide_index=True)

    st.markdown("### 📝 توضیح هر عدد")
    details = [
        ("TraderBot — 84% در 10 روز", "ربات چند-استراتژی (بولینجر کامل/نیمه + هیکن‌آشی RSI + شندلر) روی بیت‌کوین. عدد مربوط به یک دورهٔ ۱۰ روزهٔ خاص بازار است؛ در بازارهای دیگر تکرارپذیری آن تضمین نمی‌شود."),
        ("SP2L_Advanced — وین‌ریت 84٪، PF=5.5، بازده 43٪", "استراتژی اسپایک+گپ روی طلا (XAUUSD) در تایم M1. بک‌تست کامل آن در تب «SP2L پیشرفته» قابل اجراست (با متاتریدر)."),
        ("LeverageLongRun — وین‌ریت 85٪، سود 1700٪", "استراتژی مقالهٔ Leverage for the Long Run: سیگنال از SPY با SMA-100 و اجرای خرید روی UPRO (لوریج ×3). بک‌تستش همین‌جا با هر بازهٔ تاریخی قابل اجراست."),
        ("VWAP_BB_RSI — وین‌ریت 62٪", "اسکالپر ۵ دقیقه‌ای روی آلت‌کوین‌ها با VWAP + بولینگر + RSI."),
        ("CE_ZLSMA_HA_ATR — سود 1700٪", "نسخهٔ ATR-دار استراتژی شندلر/هیکن‌آشی. توجه: این نسخه همان باگ بالقوهٔ پاس‌دادن ATR بدون stopLossWithAtr را دارد."),
        ("MichaelHarrisSplit — سود 370٪", "استراتژی Split از کتاب «Profitability and Systematic Trading» مایکل هریس، بک‌تست روی CARDANO/H4."),
        ("Marco's Strategy — 4900٪ در 10 سال", "در README ذکر شده اما فایل مستقلی برای آن در ریپو نیست (احتمالاً در ویدیوهای یوتیوب نویسنده تشریح شده)."),
    ]
    for title, desc in details:
        with st.expander(f"📌 {title}"):
            st.markdown(desc)

    st.markdown("### ⚖️ یادآوری مهم")
    st.markdown(
        """<div class="warn-box">🎲 وین‌ریت به‌تنهایی معیار سودآوری نیست — معامله با نسبت ریسک/ریوارد متفاوت می‌تواند
        با وین‌ریت ۴۰٪ سودده و با وین‌ریت ۹۰٪ زیان‌ده باشد. همیشه <b>پروفیت‌فاکتور، دراودان و تعداد معامله</b> را
        کنار وین‌ریت ببینید (همه در خروجی بک‌تست‌های همین اینترفیس موجودند).<br>
        ⚠️ هیچ‌کدام از این اعداد توصیهٔ مالی نیست؛ قبل از حساب واقعی حتماً روی حساب دمو تست کنید.</div>""",
        unsafe_allow_html=True,
    )

# ===========================================================================
# صفحه: ابزارها
# ===========================================================================
elif page == "🧰 ابزارها":
    header("ابزارهای داده و پیکربندی")

    tool_tabs = st.tabs(["📥 دریافت کندل از متاتریدر", "📐 سطوح حمایت/مقاومت", "🔧 وضعیت پیکربندی"])

    # ------------------------------------------------------------------ داده MT5
    with tool_tabs[0]:
        st.markdown("#### دریافت کندل از متاتریدر و ذخیره CSV")
        st.caption("معادل پیشرفتهٔ get.py — برای هر نماد و تایم‌فریمی که در ترمینال شما موجود است.")
        if not MT5_AVAILABLE or not status.get("initialized"):
            st.markdown(
                """<div class="warn-box">⚠️ متاتریدر در دسترس نیست. این ابزار روی سیستم ویندوزی شما (با ترمینال باز) کار می‌کند.</div>""",
                unsafe_allow_html=True,
            )
        else:
            c1, c2, c3 = st.columns(3)
            symbol = c1.text_input("نماد", "BITCOIN", key="gt_symbol").upper()
            tf_label = c2.selectbox("تایم‌فریم", list(TIMEFRAMES.keys()), key="gt_tf")
            count = c3.number_input("تعداد کندل", 100, 100000, 5000, 100, key="gt_count")
            if st.button("📥 دریافت", type="primary", key="gt_run"):
                try:
                    df = fetch_rates(symbol, TIMEFRAMES[tf_label], count)
                    st.session_state["gt_df"] = df
                    st.success(f"✅ {len(df)} کندل دریافت شد — از {df.index[0]} تا {df.index[-1]}")
                except Exception as e:
                    st.error(f"خطا: {e}")
            if "gt_df" in st.session_state:
                df = st.session_state["gt_df"]
                st.dataframe(df.tail(200), width='stretch')
                csv_bytes = df.to_csv().encode("utf-8")
                st.download_button("⬇️ دانلود CSV", csv_bytes,
                                   f"{symbol}_candles.csv", "text/csv", key="gt_dl")

    # ------------------------------------------------------------- حمایت/مقاومت
    with tool_tabs[1]:
        st.markdown("#### تشخیص سطوح حمایت و مقاومت")
        st.caption("پورت‌شده از SupportResistance/ — فایل CSV کندل را بدهید یا از متاتریدر بگیرید.")
        src = st.radio("منبع داده", ["آپلود فایل CSV", "متاتریدر (اگر متصل باشد)"], horizontal=True, key="sr_src")
        df_sr = None
        if src == "آپلود فایل CSV":
            up_sr = st.file_uploader("فایل کندل (CSV)", type=["csv"], key="sr_file")
            if up_sr is not None:
                import pandas as pd
                try:
                    df_sr = sr_tools.normalize_candles(pd.read_csv(up_sr))
                except Exception as e:
                    st.error(f"خطا در فایل: {e}")
        else:
            if MT5_AVAILABLE and status.get("initialized"):
                c1, c2, c3 = st.columns(3)
                sym = c1.text_input("نماد", "BITCOIN", key="sr_symbol").upper()
                tf2 = c2.selectbox("تایم‌فریم", list(TIMEFRAMES.keys()), index=5, key="sr_tf")
                cnt2 = c3.number_input("تعداد کندل", 100, 100000, 5000, 100, key="sr_count")
                if st.button("📥 دریافت و تحلیل", type="primary", key="sr_run"):
                    try:
                        df_sr = fetch_rates(sym, TIMEFRAMES[tf2], cnt2)
                        st.session_state["sr_df"] = df_sr
                    except Exception as e:
                        st.error(f"خطا: {e}")
                if "sr_df" in st.session_state:
                    df_sr = st.session_state["sr_df"]
            else:
                st.info("متاتریدر متصل نیست؛ از آپلود CSV استفاده کنید.")

        if df_sr is not None and len(df_sr) > 10:
            c1, c2 = st.columns(2)
            before = c1.slider("کندل قبل (before)", 2, 10, 3, key="sr_before")
            after = c2.slider("کندل بعد (after)", 2, 10, 2, key="sr_after")
            rounding = c1.slider("رقم گردکردن قیمت (−3 = هزارگان)", -5, 2, -3, key="sr_round")
            tol = c2.slider("تلورانس خوشه‌بندی [%]", 0.05, 2.0, 0.15, 0.05, key="sr_tol")

            support, resistance = sr_tools.find_support_resistance(df_sr, before, after, rounding)
            s_levels = [lvl for lvl, _ in support]
            r_levels = [lvl for lvl, _ in resistance]
            st.success(f"✅ {len(support)} حمایت و {len(resistance)} مقاومت شناسایی شد.")

            m1, m2, m3 = st.columns(3)
            m1.metric("تعداد حمایت", len(support))
            m2.metric("تعداد مقاومت", len(resistance))
            m3.metric("کندل تحلیل‌شده", len(df_sr))

            st.markdown("##### 🏆 قوی‌ترین سطوح (بیشترین برخورد)")
            sc = sr_tools.cluster_levels(support, tol)
            rc = sr_tools.cluster_levels(resistance, tol)
            cc1, cc2 = st.columns(2)
            with cc1:
                st.markdown("**حمایت‌ها**")
                st.dataframe(sc.head(15), width='stretch', hide_index=True)
            with cc2:
                st.markdown("**مقاومت‌ها**")
                st.dataframe(rc.head(15), width='stretch', hide_index=True)

            # نمودار قیمت + سطوح
            try:
                import plotly.graph_objects as go
                fig = go.Figure()
                fig.add_trace(go.Scatter(x=df_sr.index, y=df_sr["close"], mode="lines",
                                         name="Close", line=dict(color="#2d7dd2", width=1.4)))
                for _, row in sc.head(6).iterrows():
                    fig.add_hline(y=row["level"], line_dash="dot", line_color="green",
                                  annotation_text=f"حمایت {row['level']:,.0f} ({int(row['touches'])}×)")
                for _, row in rc.head(6).iterrows():
                    fig.add_hline(y=row["level"], line_dash="dot", line_color="red",
                                  annotation_text=f"مقاومت {row['level']:,.0f} ({int(row['touches'])}×)")
                fig.update_layout(height=460, margin=dict(l=10, r=10, t=30, b=10),
                                  title="قیمت و سطوح کلیدی")
                st.plotly_chart(fig, width='stretch')
            except Exception:
                st.line_chart(df_sr["close"])

            # دانلود فایل‌های سازگار با ربات‌ها
            d1, d2 = st.columns(2)
            import csv as _csv
            import io as _io
            def _levels_csv(levels):
                buf = _io.StringIO()
                w = _csv.writer(buf, quoting=_csv.QUOTE_NONNUMERIC)
                w.writerow(levels)
                return buf.getvalue().encode("utf-8")
            d1.download_button("⬇️ دانلود support.csv", _levels_csv(s_levels),
                               "support.csv", "text/csv", key="sr_sup")
            d2.download_button("⬇️ دانلود resistance.csv", _levels_csv(r_levels),
                               "resistance.csv", "text/csv", key="sr_res")
            st.caption("این دو فایل را کنار TraderBot.py / EasyBotWithSupportResistance.py قرار دهید تا فیلتر سطوح فعال شود.")

    # ------------------------------------------------------------------ پیکربندی
    with tool_tabs[2]:
        st.markdown("#### وضعیت پیکربندی اجزای مجموعه")

        # تلگرام
        tg_path = catalog.CODE_DIR / "TelegramBot.py"
        tg_src = tg_path.read_text(encoding="utf-8", errors="replace") if tg_path.exists() else ""
        tg_token_filled = "token = ''" not in tg_src.replace('token = ""', "token = ''")
        t1, t2 = st.columns([3, 1])
        t1.markdown("**telegram:** اعلان‌های ربات‌ها به تلگرام")
        t2.markdown("🟢 فعال" if tg_token_filled else "⚪ توکن خالی")
        if not tg_token_filled:
            st.markdown(
                """<div class="info-box">برای فعال‌سازی اعلان‌های تلگرام:
                ۱) از @BotFather یک ربات بسازید و توکن را بگیرید<br>
                ۲) chatId خود را از @userinfobot بگیرید<br>
                ۳) هر دو را در <code>code/TelegramBot.py</code> و <code>code/SP2L/TelegramBot.py</code> وارد کنید<br>
                ۴) اگر پروکسی لازم دارید ip/port را تنظیم کنید (پیش‌فرض 127.0.0.1:1090 فعال است؛ اگر پروکسی ندارید useProxy=False کنید)<br>
                ۵) در Meta.py مقدار <code>Meta.teleBotMessage = True</code> بگذارید</div>""",
                unsafe_allow_html=True,
            )

        # CoinEx
        coinex_path = catalog.CODE_DIR / "access_id_secret_key.csv"
        t1, t2 = st.columns([3, 1])
        t1.markdown("**CoinEx:** اتصال به صرافی (فایل access_id_secret_key.csv)")
        t2.markdown("🟢 موجود" if coinex_path.exists() else "⚪ یافت نشد")
        if not coinex_path.exists():
            st.markdown(
                """<div class="info-box">برای استفاده از CoinexApi.py یک فایل با نام
                <code>access_id_secret_key.csv</code> در پوشهٔ code بسازید با این محتوا:
                <pre>access_id,مقدار-Access-ID-شما
secret_key,مقدار-Secret-Key-شما</pre>
                🔒 کلیدها را هرگز کامیت نکنید و در حساب صرافی محدودیت برداشت بگذارید.</div>""",
                unsafe_allow_html=True,
            )

        # فایل‌های سطوح
        sup_path = catalog.CODE_DIR / "support.csv"
        res_path = catalog.CODE_DIR / "resistance.csv"
        t1, t2 = st.columns([3, 1])
        t1.markdown("**سطوح حمایت/مقاومت:** فایل‌های support.csv و resistance.csv برای TraderBot")
        t2.markdown("🟢 موجود" if (sup_path.exists() and res_path.exists()) else "⚪ یافت نشد")
        if not (sup_path.exists() and res_path.exists()):
            st.markdown(
                """<div class="info-box">از تب «سطوح حمایت/مقاومت» همین صفحه این دو فایل را بسازید و در پوشهٔ
                <code>code</code> کنار TraderBot.py قرار دهید.</div>""",
                unsafe_allow_html=True,
            )

        # pandas-ta
        try:
            import pandas_ta  # noqa
            pta = True
        except Exception:
            pta = False
        t1, t2 = st.columns([3, 1])
        t1.markdown("**pandas-ta:** لازم برای TraderBot و CE_ZLSMA_HA (پایتون ≥ ۳.۱۲ لازم دارد)")
        t2.markdown("🟢 نصب" if pta else "⚪ نصب نیست")

# ===========================================================================
# صفحه: دانلود پکیج
# ===========================================================================
elif page == "⬇️ دانلود پکیج":
    header("دانلود پکیج کامل برای اجرا روی سیستم خودتان")

    st.markdown(
        """<div class="info-box">📦 این پکیج شامل <b>تمام کد ربات‌ها + همین اینترفیس + requirements.txt +
        راهنمای فارسی</b> است. آن را باز کنید، وابستگی‌ها را نصب کنید و
        <code>streamlit run app.py</code> بزنید تا همین مرکز کنترل روی سیستم خودتان بالا بیاید.</div>""",
        unsafe_allow_html=True,
    )

    import build_toolkit

    col1, col2 = st.columns(2)
    with col1:
        if st.button("🔄 ساخت/بروزرسانی پکیج ZIP", type="primary", width='stretch'):
            with st.spinner("در حال ساخت پکیج..."):
                build_toolkit.build_zip(force=True)
            st.toast("پکیج ساخته شد.")
            st.rerun()
    with col2:
        if st.button("🗑️ ساخت مجدد (اگر تغییراتی داده‌اید)", width='stretch'):
            build_toolkit.build_zip(force=True)
            st.rerun()

    # اگر zip نبود، اول بساز
    try:
        zip_path = build_toolkit.build_zip()
    except Exception as e:
        zip_path = None
        st.error(f"خطا در ساخت پکیج: {e}")

    if zip_path and zip_path.exists():
        info = build_toolkit.zip_info()
        st.markdown(
            f"""<div class="ok-box">✅ پکیج آماده است — <b>{info['files']:,} فایل</b> | حجم ≈ <b>{info['size_mb']:.2f} MB</b></div>""",
            unsafe_allow_html=True,
        )
        with open(zip_path, "rb") as f:
            st.download_button(
                "⬇️ دانلود PythonTraderBot_ControlCenter.zip",
                f.read(),
                zip_path.name,
                "application/zip",
                width='stretch',
                type="primary",
            )

    st.markdown("---")
    st.markdown("### فایل‌های تک‌به‌تک")

    req_path = catalog.REPO_ROOT / "requirements.txt"
    if req_path.exists():
        with open(req_path, "rb") as f:
            st.download_button("⬇️ requirements.txt", f.read(), "requirements.txt",
                               "text/plain", width='stretch')

    guide_path = catalog.REPO_ROOT / "START_HERE_FA.md"
    if guide_path.exists():
        with open(guide_path, "rb") as f:
            st.download_button("⬇️ راهنمای فارسی (START_HERE_FA.md)", f.read(),
                               "START_HERE_FA.md", "text/markdown", width='stretch')

    st.markdown("### 🔧 مراحل نصب روی سیستم خودتان")
    st.markdown(
        """
```
1) پایتون 3.12 را نصب کنید (برای pandas-ta لازم است)      → python.org
2) فایل ZIP را باز کنید و در یک پوشه استخراج نمایید
3) در همان پوشه:        pip install -r requirements.txt
4) برای ربات‌های متاتریدر: متاتریدر ۵ را نصب و لاگین کنید (فقط ویندوز)
5) اجرای اینترفیس:      streamlit run dashboard/app.py
6) مرورگر:              http://localhost:8501
```
"""
    )

# ===========================================================================
# صفحه: راهنما
# ===========================================================================
elif page == "📖 راهنما":
    header("راهنمای کامل استفاده")

    with st.expander("🚀 راه‌اندازی سریع (۵ دقیقه)", expanded=True):
        st.markdown(
            """
**روی ویندوز (برای همهٔ امکانات):**
1. پایتون **3.12** نصب کنید (چون pandas-ta فقط با 3.12+ نصب می‌شود)
2. پکیج ZIP را از صفحهٔ «⬇️ دانلود» بگیرید و باز کنید
3. `pip install -r requirements.txt`
4. ترمینال MetaTrader 5 را باز کنید و به حساب (ترجیحاً **دمو**) لاگین کنید
5. `streamlit run dashboard/app.py`
6. در صفحهٔ «ربات‌های زنده» دکمهٔ اجرای هر ربات را بزنید؛ لاگ زنده را همان‌جا ببینید

**بدون متاتریدر (هر سیستم‌عاملی):**
- بک‌تست‌های «مارکوف» و «لوریج SPY→UPRO» فقط اینترنت می‌خواهند (yfinance)
- بک‌تست «اسکالپر HA_RSI» و «بهینه‌ساز SMA» با آپلود فایل CSV کندل کار می‌کنند
- ربات «تحلیل احساسات اخبار» هم مستقل از متاتریدر است
"""
        )

    with st.expander("🤖 مدیریت ربات‌های زنده"):
        st.markdown(
            """
- هر ربات با یک **subprocess** جداگانه اجرا می‌شود؛ توقفش از همان صفحه
- لاگ هر ربات در `dashboard/logs/` ذخیره می‌شود و همیشه قابل مرور است
- ربات‌ها با **شمارهٔ magic** جدا از هم روی یک حساب معامله می‌کنند:
  `1=BB_Full`، `2=BB_Half`، `3=HA_RSI_CE_EMA`، `4=CE_ZLSMA`، `5=VWAP_BB_RSI`، `8=SP2L`، `0=EasyBot`
- نماد و حجم هر ربات داخل خود فایلش در `symbols_list` تعریف شده — قبل از اجرا ویرایشش کنید
- **TraderBot** به `support.csv` و `resistance.csv` کنار خودش نیاز دارد؛ از صفحهٔ ابزارها بسازید
- پیشنهاد: همیشه اول **حساب دمو**؛ و فقط یک‌بار یک استراتژی را تست کنید
"""
        )

    with st.expander("📈 راهنمای بک‌تست‌ها"):
        st.markdown(
            """
| بک‌تست | دادهٔ لازم | خروجی |
|---|---|---|
| زنجیرهٔ مارکوف | yfinance (اینترنت) | وین‌ریت/بازده هر نماد + تجمیعی |
| لوریج SPY→UPRO | yfinance (اینترنت) | منحنی سرمایه + دراودان + معاملات |
| اسکالپر HA_RSI | CSV کندل M1 | وین‌ریت + پروفیت‌فاکتور + معاملات |
| بهینه‌ساز SMA | CSV کندل | بهترین پارامترها + کل نتایج |
| مایکل هریس | متاتریدر (CARDANO H4) | نتیجه + وین‌ریت |
| SP2L پیشرفته | متاتریدر (XAUUSD M1) | win_rate/profit_factor/max_drawdown |

💡 فایل CSV کندل را می‌توانید از متاتریدر (صفحهٔ ابزارها)، از `get.py`، یا خروجی手动 ترمینال بگیرید.
ستون‌های لازم: `time, open, high, low, close` (حجم اختیاری).
"""
        )

    with st.expander("⚠️ نکات ایمنی و ریسک"):
        st.markdown(
            """
- 🎓 این مجموعه **آموزشی** است؛ اعداد README ادعای نویسنده‌اند و تضمینی نیستند
- 🧪 قبل از پول واقعی: حساب دمو + حداقل چند هفته اجرا
- 🐞 باگ‌های شناخته‌شده (در نسخهٔ کپی Meta.py ریشه، باگ تریلینگ TrailingBot و فراخوانی TeleBot اصلاح شده):
  - در `TraderBot.py` (خط ~586) و `CE_ZLSMA_HA_ATR.py` (خط ~210) مقادیر ATR بدون `stopLossWithAtr=True` پاس می‌شوند — SL/TP ممکن است اشتباه محاسبه شود
  - آستانه‌های 600/1100/100 در BB_Full برای بیت‌کوین هاردکد شده‌اند
  - زمان ورود ۴ساعته با فرض تایم‌زون سرور روسیه تنظیم شده و با DST به‌هم می‌ریزد
- 🔑 کلیدهای API را هیچ‌وقت کامیت نکنید؛ فایل `access_id_secret_key.csv` را خارج از گیت نگه دارید
"""
        )

    with st.expander("🧩 معماری و توسعه"):
        st.markdown(
            """
- **Meta.py**: لایهٔ اجرا (سفارش، تریلینگ، مدیریت بازار بسته). برای اتصال به صرافی دیگر فقط این کلاس را عوض کنید
- **CoinexApi.py**: لایهٔ مشابه برای صرافی CoinEx
- **TelegramBot.py**: اعلان‌ها؛ در Meta.py با `Meta.teleBotMessage=True` فعال می‌شود
- برای افزودن استراتژی جدید: تابعی بنویسید که `(buy, sell)` برگرداند و به `Meta.run()` بدهید
- این اینترفیس (`dashboard/`) کاملاً مستقل از ربات‌هاست؛ می‌توانید صفحه/بک‌تست جدید اضافه کنید
"""
        )

    st.markdown("---")
    st.caption("📺 آموزش‌های ویدیویی نویسنده: youtube.com/@alirezasadabadi — این اینترفیس برای ریپازیتوری PythonTraderBot ساخته شده است.")

