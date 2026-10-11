"""店頭価格（週次）の今後数週間の見通しを出す。

減衰トレンド付きの指数平滑法（Holt の damped trend）を使う。直近の流れを延ばしつつ、
先へ行くほど傾きを弱めるので、値上がり・値下がりが永遠に続くような予想にはならない。
幅（low〜high）は過去の予想の外れ方から出した目安で、約80%の確率でこの中に入る想定。
"""

from __future__ import annotations

import datetime as dt
import math
from itertools import product

HORIZON = 8  # 何週先まで出すか
Z80 = 1.2816  # 正規分布で80%区間


def _fit(values: list[float], alpha: float, beta: float, phi: float):
    """1期先予測の誤差列と、最後の水準・傾きを返す"""
    level, trend = values[0], values[1] - values[0]
    errors = []
    for y in values[1:]:
        pred = level + phi * trend
        errors.append(y - pred)
        new_level = alpha * y + (1 - alpha) * pred
        trend = beta * (new_level - level) + (1 - beta) * phi * trend
        level = new_level
    return errors, level, trend


def _best_params(values: list[float]):
    grid = [0.1 * i for i in range(1, 10)]
    best = None
    for alpha, beta, phi in product(grid, grid, (0.8, 0.85, 0.9, 0.95, 0.98)):
        errors, _, _ = _fit(values, alpha, beta, phi)
        sse = sum(e * e for e in errors[4:])  # 立ち上がりの数週は除く
        if best is None or sse < best[0]:
            best = (sse, alpha, beta, phi)
    return best[1:]


def _project(level: float, trend: float, phi: float, h: int) -> float:
    return level + sum(phi**i for i in range(1, h + 1)) * trend


def backtest(values: list[float], h: int = 4, start: int = 30) -> dict | None:
    """過去の各時点で h 週先を予想していたら、どれくらい外れたか（平均誤差、円）"""
    model, naive = [], []
    for t in range(start, len(values) - h):
        past = values[: t + 1]
        alpha, beta, phi = _best_params(past)
        _, level, trend = _fit(past, alpha, beta, phi)
        actual = values[t + h]
        model.append(abs(_project(level, trend, phi, h) - actual))
        naive.append(abs(past[-1] - actual))
    if not model:
        return None
    return {
        "weeks_ahead": h,
        "model_mae": round(sum(model) / len(model)),
        "naive_mae": round(sum(naive) / len(naive)),
        "samples": len(model),
    }


def make_forecast(weeks: list[dict]) -> dict | None:
    """weeks は retail_weekly.weeks（古い順）。予想できるだけのデータがなければ None"""
    if len(weeks) < 20:
        return None
    values = [float(w["average"]) for w in weeks]
    alpha, beta, phi = _best_params(values)
    errors, level, trend = _fit(values, alpha, beta, phi)
    recent = errors[-26:]
    sigma = math.sqrt(sum(e * e for e in recent) / len(recent))

    last_start = dt.date.fromisoformat(weeks[-1]["week_start"])
    points = []
    for h in range(1, HORIZON + 1):
        mid = _project(level, trend, phi, h)
        # 先になるほど不確かさが増える。h**0.75 は過去データで80%前後が幅に収まるよう合わせた値
        spread = Z80 * sigma * h**0.75
        start = last_start + dt.timedelta(weeks=h)
        points.append({
            "week_start": start.isoformat(),
            "week_end": (start + dt.timedelta(days=6)).isoformat(),
            "mid": round(mid),
            "low": round(mid - spread),
            "high": round(mid + spread),
        })

    change = points[3]["mid"] - values[-1]  # 4週後の変化
    threshold = 0.01 * values[-1]  # 1%未満の動きは横ばい扱い
    direction = "down" if change < -threshold else "up" if change > threshold else "flat"
    return {
        "method": "減衰トレンド付き指数平滑法（過去の店頭価格のみ）",
        "based_on": weeks[-1]["week_start"],
        "direction": direction,
        "weeks": points,
        "backtest": backtest(values),
    }
