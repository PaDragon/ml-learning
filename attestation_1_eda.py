"""
Промежуточная аттестация 1 — разведочный анализ (EDA)
База: develop_issues | VIEW: v_attestation_ml

Запуск:
  pip install -r requirements.txt
  python attestation_1_eda.py

Или откройте attestation_1_eda.ipynb в Jupyter Notebook.
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# --- Настройки подключения (при необходимости измените) ---
# PostgreSQL 5433 слушает 0.0.0.0 на VM (внешний доступ включён).
# Варианты с Windows:
#   1) PuTTY tunnel: Local 5433 -> guest:5433  →  DB_HOST = "127.0.0.1"
#   2) VirtualBox NAT / LAN: IP VM 10.0.2.15  →  DB_HOST = "10.0.2.15"
#   3) CSV уже в data/ — БД не нужна для EDA в Jupyter
DB_HOST = "127.0.0.1"
DB_PORT = 5433
DB_NAME = "develop_issues"
DB_USER = "admin"
DB_PASSWORD = "admin"

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
FIGURES_DIR = BASE_DIR / "figures"
DATA_DIR.mkdir(exist_ok=True)
FIGURES_DIR.mkdir(exist_ok=True)

RAW_CSV = DATA_DIR / "develop_issues_dataset.csv"
CLEAN_CSV = DATA_DIR / "develop_issues_dataset_clean.csv"

# Стиль графиков — простой и читаемый
sns.set_theme(style="whitegrid", font_scale=1.0)
plt.rcParams["figure.figsize"] = (8, 5)


def load_data() -> pd.DataFrame:
    """Загрузка из PostgreSQL. Если БД недоступна — из CSV."""
    if RAW_CSV.exists():
        print(f"Читаем готовый CSV: {RAW_CSV}")
        return pd.read_csv(RAW_CSV)

    from sqlalchemy import create_engine

    conn_str = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    engine = create_engine(conn_str)
    query = "SELECT * FROM v_attestation_ml"
    print("Загружаем данные из VIEW v_attestation_ml ...")
    df = pd.read_sql(query, engine)
    df.to_csv(RAW_CSV, index=False)
    print(f"Сохранено: {RAW_CSV}")
    return df


def basic_eda(df: pd.DataFrame) -> None:
    """Первичный осмотр данных."""
    print("\n=== Первые 5 строк ===")
    print(df.head())

    print("\n=== Размер таблицы ===")
    print(f"Строк: {len(df)}, столбцов: {len(df.columns)}")

    print("\n=== Типы и пропуски ===")
    print(df.info())

    print("\n=== Описательная статистика (числовые) ===")
    print(df.describe())

    print("\n=== Целевая переменная is_sla_breached ===")
    print(df["is_sla_breached"].value_counts())
    print(df["is_sla_breached"].value_counts(normalize=True).round(3))


def clean_data(df: pd.DataFrame) -> pd.DataFrame:
    """
    Простая очистка:
    1. Удаляем строки без allowed_days (некорректный SLA).
    2. story_points: пропуски → медиана.

    Важно: строки-«выбросы» по hours_to_complete НЕ удаляем.
    Время выполнения почти дублирует целевую переменную (нарушение = выполнение
    дольше срока), поэтому IQR-фильтр удалял бы почти только нарушения SLA
    и смещал баланс классов (проверено: все удалённые строки были is_sla_breached=1).
    """
    clean = df.copy()
    before = len(clean)

    clean = clean[clean["allowed_days"].notna() & (clean["allowed_days"] > 0)]
    print(f"\nПосле удаления некорректного allowed_days: {before} -> {len(clean)}")

    if clean["story_points"].isna().any():
        median_sp = clean["story_points"].median()
        clean["story_points"] = clean["story_points"].fillna(median_sp)
        print(f"story_points: пропуски заполнены медианой ({median_sp})")

    return clean


def breach_rate_table(df: pd.DataFrame, column: str) -> pd.DataFrame:
    """Доля нарушений SLA по категории — как AVG(is_overdue) в SQL."""
    tmp = (
        df.groupby(column)["is_sla_breached"]
        .agg(cnt="count", breach_pct=lambda s: round(s.mean() * 100, 2))
        .reset_index()
        .sort_values("breach_pct", ascending=False)
    )
    return tmp


def plot_target_distribution(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots()
    sns.countplot(data=df, x="is_sla_breached", hue="is_sla_breached", ax=ax, palette="Set2", legend=False)
    ax.set_title("Распределение целевой переменной is_sla_breached")
    ax.set_xlabel("0 = в срок, 1 = нарушение SLA")
    ax.set_ylabel("Количество назначений")
    plt.tight_layout()
    path = FIGURES_DIR / "01_target_distribution.png"
    plt.savefig(path, dpi=120)
    plt.close()
    print(f"График: {path}")


def plot_breach_by_category(df: pd.DataFrame, column: str, title: str, filename: str) -> None:
    stats = breach_rate_table(df, column)
    fig, ax = plt.subplots()
    sns.barplot(data=stats, x=column, y="breach_pct", hue=column, ax=ax, palette="Blues_d", legend=False)
    ax.set_title(title)
    ax.set_ylabel("Доля нарушений SLA, %")
    ax.set_xlabel(column)
    plt.xticks(rotation=30, ha="right")
    plt.tight_layout()
    path = FIGURES_DIR / filename
    plt.savefig(path, dpi=120)
    plt.close()
    print(f"График: {path}")


def plot_allowed_days_boxplot(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots()
    sns.boxplot(data=df, x="is_sla_breached", y="allowed_days", hue="is_sla_breached", ax=ax, palette="Pastel1", legend=False)
    ax.set_title("Срок SLA (allowed_days) vs нарушение")
    ax.set_xlabel("is_sla_breached")
    ax.set_ylabel("allowed_days")
    plt.tight_layout()
    path = FIGURES_DIR / "05_allowed_days_boxplot.png"
    plt.savefig(path, dpi=120)
    plt.close()
    print(f"График: {path}")


def plot_correlation_heatmap(df: pd.DataFrame) -> None:
    numeric_cols = [
        "is_sla_breached",
        "allowed_days",
        "hours_to_complete",
        "story_points",
        "experience_years",
        "assignments_on_task",
    ]
    available = [c for c in numeric_cols if c in df.columns]
    corr = df[available].corr(numeric_only=True)

    fig, ax = plt.subplots(figsize=(8, 6))
    sns.heatmap(corr, annot=True, fmt=".2f", cmap="coolwarm", center=0, ax=ax)
    ax.set_title("Корреляция числовых признаков с is_sla_breached")
    plt.tight_layout()
    path = FIGURES_DIR / "06_correlation_heatmap.png"
    plt.savefig(path, dpi=120)
    plt.close()
    print(f"График: {path}")


def main() -> None:
    df = load_data()
    basic_eda(df)

    df_clean = clean_data(df)
    df_clean.to_csv(CLEAN_CSV, index=False)
    print(f"\nОчищенный датасет: {CLEAN_CSV}")

    print("\n=== H2: breach % по типу задачи ===")
    print(breach_rate_table(df_clean, "task_type"))

    print("\n=== H4: breach % по роли ===")
    print(breach_rate_table(df_clean, "developer_role"))

    print("\n=== H7: breach % по образованию ===")
    print(breach_rate_table(df_clean, "education_level"))

    experience_buckets = pd.cut(
        df_clean["experience_years"],
        bins=[-1, 2, 5, 10**6],
        labels=["0-2 года", "3-5 лет", "6+ лет"],
    )
    print("\n=== H7: breach % по опыту ===")
    print(breach_rate_table(df_clean.assign(experience_bucket=experience_buckets), "experience_bucket"))

    plot_target_distribution(df_clean)
    plot_breach_by_category(df_clean, "task_type", "H2: нарушения SLA по типу задачи", "02_breach_by_task_type.png")
    plot_breach_by_category(df_clean, "developer_role", "H4: нарушения SLA по роли", "03_breach_by_role.png")
    plot_breach_by_category(df_clean, "industry", "H9: нарушения SLA по отрасли заказчика", "04_breach_by_industry.png")
    plot_allowed_days_boxplot(df_clean)
    plot_correlation_heatmap(df_clean)

    print("\nГотово. Откройте папку figures/ или attestation_1_eda.ipynb для просмотра.")


if __name__ == "__main__":
    main()
