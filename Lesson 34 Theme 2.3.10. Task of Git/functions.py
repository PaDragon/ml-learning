# Урок 34. Тема: 2.3.10. Git контроль версий

# Задание (часть с кодом): написать и проверить функции
#   1) list_gen(a: int, b: int, length: int) -> list  — список из length случайных
#      целых чисел от a до b (равномерное распределение)
#   2) freq_dict(numbers: list) -> dict  — частотный ряд:
#      [1, 2, 3, 1, 2, 2] -> {1: 2, 2: 3, 3: 1}
#   3) describe_list(numbers: list) -> dict  — минимум, среднее, медиана, мода,
#      максимум для значений списка
#
# Далее: положить файлы в репозиторий GitHub и сделать commit + push
# (пошаговая инструкция — в урок_34.md, сами команды выполняет студент).

# Запуск: python functions.py

import random
import statistics

SEED = 42                # фиксируем случайность — результат воспроизводим
random.seed(SEED)


# --- Функция 1: генератор списка случайных целых ---
def list_gen(a: int, b: int, length: int) -> list:
    """Список из length случайных целых чисел от a до b (включительно)."""
    result = []
    for i in range(length):
        result.append(random.randint(a, b))
    return result


# --- Функция 2: частотный ряд ---
def freq_dict(numbers: list) -> dict:
    """Сколько раз каждое число встречается в списке.
    Пример из задания: [1, 2, 3, 1, 2, 2] -> {1: 2, 2: 3, 3: 1}"""
    result = {}
    for n in numbers:
        if n in result:
            result[n] = result[n] + 1   # уже видели — увеличиваем счётчик
        else:
            result[n] = 1               # первый раз — начинаем с 1
    return result


# --- Функция 3: статистики списка ---
def describe_list(numbers: list) -> dict:
    """Минимум, среднее, медиана, мода и максимум списка."""
    return {
        "min": min(numbers),
        "mean": round(statistics.mean(numbers), 2),
        "median": statistics.median(numbers),
        "mode": statistics.mode(numbers),
        "max": max(numbers),
    }


# --- Проверка ---
if __name__ == "__main__":
    # функция 1
    my_list = list_gen(1, 10, 15)
    print("list_gen(1, 10, 15) =", my_list)
    assert len(my_list) == 15                     # длина правильная
    assert all(1 <= x <= 10 for x in my_list)     # все числа в диапазоне

    # функция 2 — пример из задания
    assert freq_dict([1, 2, 3, 1, 2, 2]) == {1: 2, 2: 3, 3: 1}
    print("freq_dict([1, 2, 3, 1, 2, 2]) =", freq_dict([1, 2, 3, 1, 2, 2]))

    # функция 3 — проверка на простом примере
    assert describe_list([1, 2, 2, 3, 4]) == {"min": 1, "mean": 2.4,
                                              "median": 2, "mode": 2, "max": 4}
    print("describe_list([1, 2, 2, 3, 4]) =", describe_list([1, 2, 2, 3, 4]))

    # все вместе: статистики случайного списка
    stats = describe_list(list_gen(1, 5, 20))
    print("describe_list(list_gen(1, 5, 20)) =", stats)

    print("\nВсе проверки пройдены!")
