# 🌊 DockFlow for macOS

> **Плавное управление Доком и умное закрытие окон (⌘Q) в стиле macOS 27.**  
> *Эффект Джинна по клику на Док, мгновенное завершение приложений по красному крестику и сохранение сессий браузеров.*

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20%7C%2027.0%2B-blue?style=for-the-badge&logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange?style=for-the-badge" alt="Architecture" />
  <img src="https://img.shields.io/badge/Swift-6.4-F05138?style=for-the-badge&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License" />
</p>

> 🔱 **О проекте и авторстве:**  
> **DockFlow** является глубоко переработанным форком проекта **[DockMinimizer](https://github.com/JackTonyMa/DockMinimizer)** разработчика *JackTonyMa*.  
> В форке полностью переосмыслено поведение окон, добавлены аппаратная анимация Джинна, модуль автозавершения через CoreGraphics, сохранение сессий браузеров, адаптивная иконка и новый интерфейс в стиле macOS 27.

---

[Русский](#русский) | [English](#english)

---

## Русский

### 📌 Почему DockFlow?

В стандартной macOS есть два давних неудобства оконного менеджера, к которым сложно привыкнуть (особенно после Windows):
1. **Клик по Доку не сворачивает окно:** Если приложение уже активно, повторный клик по его иконке в Доке ничего не делает.
2. **Красный крестик не закрывает программу:** Нажатие на крестик лишь закрывает окно, оставляя фоновый процесс висеть в памяти и в Доке с точкой, требуя постоянного нажатия `⌘ + Q`.

**DockFlow** элегантно и бесшовно решает обе проблемы на уровне системы.

---

### 🚀 Что нового по сравнению с оригинальным DockMinimizer

| Возможность | Оригинальный DockMinimizer | **DockFlow (Этот форк)** |
|---|---|---|
| **Анимация Дока** | Мгновенное исчезновение (`app.hide`) | 🪄 **Настоящая плавная анимация Джинна** в Док и обратно |
| **Красный крестик** | Только скрывает окно | ❌ **Полное завершение приложения (⌘Q)** при закрытии последнего окна |
| **Вкладки браузеров** | Терялись при закрытии | 💾 **Сессии и все вкладки сохраняются** (Safari, Chrome и др.) |
| **Safari (песочница)** | Не определялось закрытие | 🛡️ **Обход через CoreGraphics** (видит реальные окна на экране) |
| **Локализация** | Только китайский и английский | 🌐 **Мультиязычность** (полная поддержка русской macOS) |
| **Интерфейс** | Базовый диалог | 🎨 **Современный UI в стиле macOS 27** (группированные карточки, SF Symbols) |
| **Иконка** | Стандартная растровая | 🔮 **Адаптивный сквиркл** с поддержкой тёмной/светлой темы и системной перекраски (Tinted Mode) |
| **Установщик** | Обычный DMG | 💿 **Дизайнерский Retina DMG** со стрелкой drag-and-drop |

---

### ✨ Ключевые функции

#### 1. 🪄 Эффект Джинна (Genie Effect) по клику на Док
* **Windows-style переключение:** Повторный клик по значку активного приложения в Доке плавно сворачивает его окно с анимацией Джинна прямо в Док.
* **Разворачивание:** Следующий клик разворачивает окно обратно с тем же эффектом.
* **Каскад:** При нескольких окнах они сворачиваются плавно друг за другом.

#### 2. ❌ Полное закрытие по красному крестику (⌘Q)
* При нажатии на красный крестик последнего открытого окна приложение завершается **целиком**, точно так же, как по нажатию `Command + Q`. Точка в Доке исчезает, память освобождается.
* **Умная работа с несколькими окнами:** Если открыто 2 или больше окон, крестик закрывает **только текущее окно**. Приложение завершится только тогда, когда закрыто последнее окно.
* **Сохранение вкладок и сессий:** Клик перехватывается до того, как окно уничтожит свои вкладки. Браузеры (Safari, Google Chrome, Яндекс и др.) успевают зафиксировать открытые вкладки и сессию. При следующем запуске всё восстанавливается!
* **Защита системы:** Системные процессы (`Finder`, `Dock` и др.) защищены и никогда не закрываются по ошибке.

#### 3. ⚡ Архитектура CoreGraphics & Безотказность
* **Без зависаний ввода:** В отличие от сырых скриптов перехвата, утилита использует безопасную обработку таймаутов `CGEventTap` и ядро Window Server (`CGWindowListCopyWindowInfo`).
* **Обход песочницы Safari:** Safari в macOS при закрытии окна переводит его в состояние `visible: false`, из-за чего обычные скрипты не видят закрытия. DockFlow опрашивает сам системный композитор экрана и надёжно закрывает Safari.

---

### 📦 Установка

1. Скачайте **`DockFlow-Installer.dmg`**.
2. Откройте образ и перетащите **DockFlow** в папку **Applications**.
3. Запустите приложение.
4. При первом запуске выдайте разрешение в:  
   `Системные настройки → Конфиденциальность и безопасность → Универсальный доступ`.

---

<br/>

## English

### 📌 About DockFlow

**DockFlow** is a native, lightweight window & dock enhancer for macOS that bridges the gap between Windows ergonomics and macOS aesthetics:
1. Clicking an active app's Dock icon smoothly minimizes it into the Dock with the native **Genie effect** and restores it on the next click.
2. Clicking the red close button completely quits the application (like `⌘ + Q`) while preserving browser tabs and window sessions.

> 🔱 **Attribution:**  
> This project is an advanced fork of **[DockMinimizer](https://github.com/JackTonyMa/DockMinimizer)** by *JackTonyMa*, significantly expanded with native Genie animations, CoreGraphics zero-window auto-termination, browser session preservation, adaptive icons, and a macOS 27 redesign.

---

### 📄 License

Distributed under the **MIT License**. Original work Copyright © 2025 JackTonyMa. Fork enhancements Copyright © 2026.
