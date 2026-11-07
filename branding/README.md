# Логотип Sumbar

<img src="sumbar-logo-adaptive.svg" width="360" alt="Sumbar">

Две встречные ленты образуют S и отсылают к обмену валют. Синий знак продолжает цветовой акцент проекта.

| Файл | Назначение |
| --- | --- |
| [sumbar-logo.svg](sumbar-logo.svg) | Полный логотип для светлого фона; надпись переведена в контуры |
| [sumbar-logo-dark.svg](sumbar-logo-dark.svg) | Полный логотип для тёмного фона |
| [sumbar-logo-adaptive.svg](sumbar-logo-adaptive.svg) | Автоматический выбор цвета надписи, используется в README |
| [sumbar-mark.svg](sumbar-mark.svg) | Отдельный знак S |
| [sumbar-logo.png](sumbar-logo.png) | Исходная растровая концепция, 2172 × 724, прозрачный фон |

Векторная адаптация повторяет идею растрового логотипа с чистой геометрией для маленьких размеров. Исходный PNG создан встроенным imagegen, [точный запрос](prompt.txt) сохранён.

Знак в приложении и в установщике берётся из [векторного PDF](../Sources/Sumbar/Resources/SumbarMark.pdf). Векторные файлы и PDF создаются одним [скриптом](../scripts/brand-assets.swift):

```sh
mkdir -p temp/module-cache
xcrun swift -module-cache-path temp/module-cache scripts/brand-assets.swift
```

Результаты генерации хранятся в Git; обычная сборка не требует повторного запуска скрипта. Команда также обновляет `web/assets/mark.svg`. [Правила использования](../docs/BRANDING.md).
