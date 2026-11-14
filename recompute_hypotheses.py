"""
Промежуточная аттестация 1 — пересчёт гипотез H1–H9 по выгрузке витрины.

Источник: data/develop_issues_dataset.csv (экспорт VIEW v_attestation_ml).
Скрипт воспроизводит все таблицы из ml_develop_issues_part1.md без обращения к БД.

Запуск:
  python recompute_hypotheses.py
"""

from pathlib import Path

import pandas as pd

BASE_DIR = Path(__file__).resolve().parent
RAW_CSV = BASE_DIR / "data" / "develop_issues_dataset.csv"


def rate_table(df: pd.DataFrame, column: str) -> pd.DataFrame:
    """Доля нарушений SLA по категории — аналог AVG(is_sla_breached) в SQL."""
    return (
        df.groupby(column, observed=True)["is_sla_breached"]
        .agg(cnt="count", breach_pct=lambda s: round(s.mean() * 100, 2))
        .reset_index()
        .sort_values("breach_pct", ascending=False)
    )


def bucket_table(df: pd.DataFrame, bucket: pd.Series, order: list[str]) -> pd.DataFrame:
    tmp = df.assign(bucket=bucket)
    table = (
        tmp.groupby("bucket", observed=True)["is_sla_breached"]
        .agg(cnt="count", breach_pct=lambda s: round(s.mean() * 100, 2))
        .reset_index()
        .set_index("bucket")
    )
    # порядок из отчёта; пустые бакеты (нет строк) не показываем
    order = [b for b in order if b in table.index]
    return table.loc[order].reset_index()


def main() -> None:
    df = pd.read_csv(RAW_CSV)

    print(f"Источник: {RAW_CSV.name}")
    print(f"Строк (завершённых назначений с SLA): {len(df)}")

    # --- H1: общая доля нарушений ---
    n = len(df)
    breaches = int(df["is_sla_breached"].sum())
    print("\n=== H1: общая доля нарушений ===")
    print(f"Всего назначений: {n}")
    print(f"Нарушений: {breaches} ({breaches / n * 100:.2f}%)")
    print(f"В срок: {n - breaches} ({(n - breaches) / n * 100:.2f}%)")
    print(f"Средняя просрочка среди нарушений, ч: {df.loc[df['is_sla_breached'] == 1, 'hours_overdue'].mean():.1f}")

    # --- H2: тип задачи ---
    print("\n=== H2: тип задачи ===")
    print(rate_table(df, "task_type").to_string(index=False))

    # --- H3: срок SLA ---
    print("\n=== H3: срок SLA (allowed_days) ===")
    ad = df["allowed_days"]
    buckets = pd.cut(
        ad,
        bins=[0, 3, 5, 7, 10**6],
        labels=["≤3 дней", "4–5 дней", "6–7 дней", "8+ дней"],
    )
    print(bucket_table(df, buckets, ["4–5 дней", "≤3 дней", "8+ дней", "6–7 дней"]).to_string(index=False))

    # --- H4: роль исполнителя ---
    print("\n=== H4: роль исполнителя ===")
    print(rate_table(df, "developer_role").to_string(index=False))

    # --- H5: story points ---
    print("\n=== H5: story points ===")
    sp = df["story_points"].fillna(df["story_points"].median())
    buckets = pd.cut(sp, bins=[0, 3, 8, 10**6], labels=["1–3 SP", "4–8 SP", "9+ SP"])
    print(bucket_table(df, buckets, ["9+ SP", "4–8 SP", "1–3 SP"]).to_string(index=False))

    # --- H6: число назначений на задаче (ping-pong) ---
    print("\n=== H6: назначений на задаче ===")
    aot = df["assignments_on_task"]
    buckets = pd.cut(aot, bins=[0, 2, 3, 10**6], labels=["1–2", "3", "4+"])
    print(bucket_table(df, buckets, ["4+", "3", "1–2"]).to_string(index=False))

    # --- H7: опыт и образование ---
    print("\n=== H7: опыт (experience_years) ===")
    ey = df["experience_years"]
    buckets = pd.cut(ey, bins=[-1, 2, 5, 10**6], labels=["0–2 года", "3–5 лет", "6+ лет"])
    print(bucket_table(df, buckets, ["0–2 года", "3–5 лет", "6+ лет"]).to_string(index=False))
    print("\n=== H7: образование (education_level) ===")
    print(rate_table(df, "education_level").to_string(index=False))

    # --- H8: high_priority ---
    print("\n=== H8: метка high_priority ===")
    print(rate_table(df, "has_high_priority").to_string(index=False))

    # --- H9: отрасль заказчика ---
    print("\n=== H9: отрасль заказчика ===")
    print(rate_table(df, "industry").to_string(index=False))
    print("\nЗаказчики:")
    print(
        df.groupby(["organization_name", "industry"], observed=True)["is_sla_breached"]
        .agg(cnt="count", breach_pct=lambda s: round(s.mean() * 100, 2))
        .reset_index()
        .sort_values("breach_pct", ascending=False)
        .to_string(index=False)
    )

    # --- Разброс по разработчикам (уровень оценки) ---
    by_dev = df.groupby("developer_id")["is_sla_breached"].mean() * 100
    print("\n=== Разброс breach rate по разработчикам ===")
    print(f"Разработчиков: {len(by_dev)}, min {by_dev.min():.1f}%, max {by_dev.max():.1f}%")
    print("\nРаспределение по диапазонам:")
    print(
        pd.cut(by_dev, bins=[0, 25, 50, 75, 100])
        .value_counts()
        .sort_index()
        .to_string()
    )


if __name__ == "__main__":
    main()
