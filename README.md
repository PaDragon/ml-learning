# Промежуточная аттестация 1 — SLA в develop_issues

**Тема:** прогноз нарушения SLA исполнителями (`is_sla_breached`) на уровне `task_assignment`.
Постановка задачи — в [`main_work_1.md`](main_work_1.md).
Полный отчёт по гипотезам — [`ml_develop_issues_part1.md`](ml_develop_issues_part1.md).
Домашние задания курса добавляются папками `Lesson NN ...` (начиная с Lesson 45).

## Порядок запуска

```bash
# 1. Витрина: функция add_business_days + VIEW v_attestation_ml
psql -h 127.0.0.1 -p 5433 -U admin -d develop_issues -f 01_setup_view.sql

# 2. SQL-проверка гипотез (в стиле преподавателя: CTE + GROUP BY)
psql -h 127.0.0.1 -p 5433 -U admin -d develop_issues -f 02_hypotheses.sql

# 3. Экспорт CSV (путь на сервере БД; либо \copy из psql-клиента)
psql -h 127.0.0.1 -p 5433 -U admin -d develop_issues -f 03_export_csv.sql

# 4. Пересчёт всех таблиц гипотез по CSV (без БД)
python recompute_hypotheses.py

# 5. EDA: очистка, таблицы, графики
pip install -r requirements.txt
python attestation_1_eda.py        # или открыть attestation_1_eda.ipynb в Jupyter
```

Если PostgreSQL недоступен, EDA и пересчёт работают офлайн — читают готовый
`data/develop_issues_dataset.csv` (выгрузка витрины от 14.11, 2 590 строк).

## Структура

| Путь | Назначение |
|------|-----------|
| `01_setup_view.sql` | функция рабочих дней + витрина `v_attestation_ml` |
| `02_hypotheses.sql` | H1/H2/H4/H7 + уровни developer/organization/project |
| `03_export_csv.sql` | `\copy` витрины в CSV |
| `export_dataset.sql` | `CREATE OR REPLACE VIEW v_attestation_ml` — запрос, формирующий витрину (источник CSV); ноутбук работает только с выгруженным CSV |
| `recompute_hypotheses.py` | все таблицы H1–H9 по CSV (воспроизведение отчёта) |
| `attestation_1_eda.py` / `.ipynb` | EDA: очистка, таблицы breach-rate, 6 графиков |
| `data/develop_issues_dataset.csv` | сырая выгрузка витрины (2 590 строк) |
| `data/develop_issues_dataset_clean.csv` | после очистки (удалён только некорректный `allowed_days`, пропуски `story_points` → медиана) |
| `figures/` | 6 графиков (целевая, тип задачи, роль, отрасль, boxplot, корреляции) |
| `Lesson 45 Theme 3.1.2. Task of Linear Regression/` | домашнее задание: линейная регрессия по датасету аттестации |
| `Lesson 46 Theme 3.1.3. Task of Polynomial Regression/` | домашнее задание: полиномиальная регрессия, Lasso/Ridge |
| `Lesson 47 Theme 3.1.4. Task of Classification/` | домашнее задание: классификация (KNN, PR/ROC, порог) |
| `Lesson 49 Theme 3.1.5. Task of Clustering/` | домашнее задание: кластеризация (K-Means, иерархическая) |
| `Lesson 50 Theme 3.1.6. Task of Logistic Regression/` | домашнее задание: логистическая регрессия (ROC-AUC 0.83) |
| `Lesson 51 Theme 3.1.7. Task of SVM and Decision Tree/` | домашнее задание: SVM и решающее дерево (GridSearchCV, F1 0.82/0.79) |
| `Lesson 53 Theme 3.1.8. Task of Ensembles/` | домашнее задание: ансамбли и бустинг (12 моделей, лучший RF F1 0.81) |
| `Lesson 34 Theme 2.3.10. Task of Git/` | домашнее задание: Git — функции list_gen, freq_dict, describe_list |

## Датасет (срез 14.11)

- 2 590 завершённых назначений с SLA;
- баланс классов: 1 114 в срок (43,01%) / 1 476 нарушений (56,99%);
- отрасли заказчиков: нефтехимия, топливная розница, энергетика.

> Числа в отчётах пересчитаны по этому CSV (`recompute_hypotheses.py`).
> H10 (время в `in_discussion`) считается отдельным SQL к `task_status_transitions` —
> признака в витрине нет.

## Почему в clean не удаляются выбросы `hours_to_complete`

Время выполнения почти дублирует целевую переменную (нарушение = выполнение дольше
срока), поэтому IQR-фильтр удалял бы почти только нарушения SLA и смещал баланс
классов (на этих данных все удаляемые строки имели `is_sla_breached = 1`).
