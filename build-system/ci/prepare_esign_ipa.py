#!/usr/bin/env python3
"""Prepare a main-app-only IPA for final ESign signing; never signs the app.

Build-time fake provisioning stays separate from the final installation identity.
Only Info.plist changes. Mach-O files, ZIP permissions, symlinks and resources
are preserved. The output MUST be re-signed before installation.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import queue
import re
import shutil
import sys
import tempfile
import threading
import zipfile


DEFAULT_PROFILE = {'bundle_id': 'app.eclipse296.lake3160', 'team_id': '336W4P3WL5', 'aps_environment': 'production'}


def validate_config(config):
    bundle_id = config['bundle_id']
    team_id = config['team_id']
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle_id):
        raise ValueError('Invalid bundle_id')
    if not re.fullmatch(r'[A-Z0-9]{10}', team_id):
        raise ValueError('Invalid team_id')
    if config['aps_environment'] not in ('production', 'development'):
        raise ValueError('APNs environment must be production or development')


def prepare(source: Path, destination: Path, config: dict):
    validate_config(config)
    bundle_id = config['bundle_id']
    team_id = config['team_id']
    if source.resolve() == destination.resolve():
        raise ValueError('Output must differ from the source IPA')
    if destination.exists():
        raise FileExistsError('Output already exists; choose a new filename')
    with zipfile.ZipFile(source) as original:
        names = original.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        if any('.appex/' in name or '/Watch/' in name for name in names):
            raise ValueError('Extensions/watch apps need their own signing plan')
        candidates = [name for name in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
        if len(candidates) != 1:
            raise ValueError('Expected exactly one main app Info.plist')
        info_path = candidates[0]
        data = original.read(info_path)
        info = plistlib.loads(data)
        previous = info['CFBundleIdentifier']
        info['CFBundleIdentifier'] = bundle_id
        # AppDelegate constructs these task identifiers from Bundle.main at runtime.
        info['BGTaskSchedulerPermittedIdentifiers'] = [
            bundle_id + item[len(previous):] if item.startswith(previous + '.') else item
            for item in info.get('BGTaskSchedulerPermittedIdentifiers', [])
        ]
        # Diagnostic expectations only; these keys do not grant any entitlement.
        info['ShadowExpectedSigningTeam'] = team_id
        info['ShadowExpectedAPNsEnvironment'] = config['aps_environment']
        info['ShadowRequiresESign'] = True
        fmt = plistlib.FMT_BINARY if data.startswith(b'bplist') else plistlib.FMT_XML
        updated = plistlib.dumps(info, fmt=fmt, sort_keys=False)
        # Publish only a complete archive, atomically and without overwriting a
        # file another process may have created while this one was preparing.
        with tempfile.TemporaryDirectory(prefix='shadow-esign-', dir=destination.parent) as folder:
            ready = Path(folder) / 'ready.ipa'
            with zipfile.ZipFile(ready, 'x') as output:
                output.comment = original.comment
                for entry in original.infolist():
                    if entry.filename == info_path:
                        output.writestr(entry, updated)
                    else:
                        with original.open(entry) as reader, output.open(entry, 'w') as writer:
                            shutil.copyfileobj(reader, writer, length=1024 * 1024)
            os.link(ready, destination)
    return bundle_id


def presets_path():
    if sys.platform == 'win32':
        base = Path(os.environ.get('APPDATA', Path.home()))
    elif sys.platform == 'darwin':
        base = Path.home() / 'Library' / 'Application Support'
    else:
        base = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    return base / 'ShadowESign' / 'profiles.json'


def load_presets(path):
    if not path.exists():
        return {'Folzy': dict(DEFAULT_PROFILE)}
    document = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(document, dict) or document.get('version') != 1 or not isinstance(document.get('profiles'), dict):
        raise ValueError('Неподдерживаемый формат наборов')
    result = {}
    for name, profile in document['profiles'].items():
        if not isinstance(name, str) or not name.strip() or len(name) > 80:
            raise ValueError('Некорректное название набора')
        validate_config(profile)
        result[name] = {key: profile[key] for key in DEFAULT_PROFILE}
    return result


def save_presets(path, profiles):
    # Store identifiers only: never persist P12/passwords, UDIDs or selected IPA paths.
    clean = {}
    for name, profile in profiles.items():
        if not name.strip() or len(name) > 80:
            raise ValueError('Название должно содержать от 1 до 80 символов')
        validate_config(profile)
        clean[name] = {key: profile[key] for key in DEFAULT_PROFILE}
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as file:
            temporary = Path(file.name)
            json.dump({'version': 1, 'profiles': clean}, file, ensure_ascii=False, indent=2)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def config_from_mobileprovision(path):
    # Metadata convenience only, not CMS/signature verification or a grant of rights.
    data = path.read_bytes()
    start = data.find(b'<?xml')
    end = data.find(b'</plist>', start)
    if start < 0 or end < 0:
        raise ValueError('Не найден XML plist в профиле')
    document = plistlib.loads(data[start:end + len(b'</plist>')])
    entitlements = document['Entitlements']
    app_identifier = entitlements['application-identifier']
    _, separator, bundle_id = app_identifier.partition('.')
    if not separator or '*' in bundle_id:
        raise ValueError('Нужен explicit App ID, wildcard-профиль не подходит')
    config = {
        'bundle_id': bundle_id,
        'team_id': entitlements['com.apple.developer.team-identifier'],
        'aps_environment': entitlements['aps-environment'],
    }
    validate_config(config)
    return config


def launch_gui():
    try:
        import tkinter as tk
        from tkinter import ttk, filedialog, messagebox
    except ImportError:
        raise SystemExit('Для окна нужен tkinter (обычно входит в Python с python.org). CLI доступен через --help.')

    root = tk.Tk()
    root.title('Shadow — наборы для ESign')
    root.geometry('760x660')
    root.minsize(730, 620)
    frame = ttk.Frame(root, padding=20)
    frame.pack(fill='both', expand=True)
    frame.columnconfigure(1, weight=1)
    ttk.Label(frame, text='Подготовка IPA для ESign', font=('', 17, 'bold')).grid(row=0, column=0, columnspan=3, sticky='w')
    ttk.Label(frame, text='Выберите набор, укажите IPA и сохраните отдельную копию.\nПосле этого подпишите её в ESign подходящим сертификатом и профилем.', wraplength=650).grid(row=1, column=0, columnspan=3, sticky='w', pady=(8, 18))
    path = presets_path()
    try:
        profiles = load_presets(path)
    except (OSError, ValueError, KeyError, TypeError) as error:
        messagebox.showerror('Не удалось открыть наборы', f'{error}\n\n{path}\nФайл не изменён.')
        root.destroy()
        return
    selected = tk.StringVar()
    name = tk.StringVar()
    fields = {key: tk.StringVar() for key in DEFAULT_PROFILE}
    source_path = tk.StringVar()
    status = tk.StringVar(value='Готово. Сертификаты и пароли не требуются для подготовки.')
    busy = False
    results = queue.Queue()

    def show_config(config):
        for key, value in config.items():
            fields[key].set(value)

    def refresh_names():
        picker['values'] = sorted(profiles)

    def choose_preset(_event=None):
        if selected.get() in profiles:
            name.set(selected.get())
            show_config(profiles[selected.get()])

    def save():
        try:
            label = name.get().strip()
            config = {key: value.get().strip() for key, value in fields.items()}
            candidate = dict(profiles)
            candidate[label] = config
            save_presets(path, candidate)
            profiles.clear()
            profiles.update(candidate)
            refresh_names()
            selected.set(label)
            status.set(f'Набор «{label}» сохранён. Для друга введите другое название.')
        except (OSError, ValueError) as error:
            messagebox.showerror('Не удалось сохранить', str(error))

    def remove():
        label = selected.get()
        if label not in profiles or not messagebox.askyesno('Удалить набор?', f'Удалить только сохранённый набор «{label}»? IPA не изменится.'):
            return
        candidate = dict(profiles)
        del candidate[label]
        try:
            save_presets(path, candidate)
        except OSError as error:
            messagebox.showerror('Ошибка', str(error))
            return
        profiles.clear()
        profiles.update(candidate)
        refresh_names()
        selected.set('')
        status.set('Набор удалён.')

    def import_profile():
        filename = filedialog.askopenfilename(title='Выберите provisioning profile', filetypes=[('Provisioning profile', '*.mobileprovision'), ('Все файлы', '*')])
        if not filename:
            return
        try:
            show_config(config_from_mobileprovision(Path(filename)))
            status.set('Поля заполнены из профиля. Это чтение метаданных, не проверка его подписи. Сохраните набор.')
        except (OSError, ValueError, KeyError, TypeError) as error:
            messagebox.showerror('Профиль не подходит', str(error))

    def choose_ipa():
        filename = filedialog.askopenfilename(title='Исходный IPA', filetypes=[('IPA', '*.ipa')])
        if filename:
            source_path.set(filename)

    def prepare_clicked():
        nonlocal busy
        if busy:
            return
        config = {key: value.get().strip() for key, value in fields.items()}
        source = Path(source_path.get())
        try:
            validate_config(config)
            if not source.is_file():
                raise ValueError('Сначала выберите исходный IPA')
        except (ValueError, KeyError) as error:
            messagebox.showerror('Проверьте поля', str(error))
            return
        label = re.sub(r'[^\w.-]+', '_', name.get().strip()) or 'User'
        filename = filedialog.asksaveasfilename(title='Новая копия для ESign', initialfile=f'Shadow-{label}-ESign.ipa', defaultextension='.ipa', filetypes=[('IPA', '*.ipa')])
        if not filename:
            return
        destination = Path(filename)
        if destination.exists():
            messagebox.showerror('Файл уже существует', 'Выберите новое имя: исходные и готовые IPA не перезаписываются.')
            return
        busy = True
        prepare_button.state(['disabled'])
        status.set('Подготовка IPA…')

        def worker():
            try:
                prepare(source, destination, config)
                results.put((True, str(destination)))
            except Exception as error:
                results.put((False, str(error)))
        threading.Thread(target=worker, daemon=False).start()

    def poll():
        nonlocal busy
        try:
            success, result = results.get_nowait()
        except queue.Empty:
            pass
        else:
            busy = False
            prepare_button.state(['!disabled'])
            status.set('Готово: подпишите новую IPA в ESign.' if success else 'Подготовка не удалась.')
            if success:
                messagebox.showinfo('IPA подготовлен', f'{result}\n\nТеперь подпишите его в ESign. Старый IPA не изменён.')
            else:
                messagebox.showerror('Ошибка подготовки', result)
        root.after(150, poll)

    def close():
        if busy:
            messagebox.showinfo('Подготовка идёт', 'Дождитесь завершения записи IPA.')
        else:
            root.destroy()

    ttk.Label(frame, text='Сохранённый набор').grid(row=2, column=0, sticky='w')
    picker = ttk.Combobox(frame, textvariable=selected, state='readonly')
    picker.grid(row=2, column=1, sticky='ew', pady=5)
    picker.bind('<<ComboboxSelected>>', choose_preset)
    ttk.Button(frame, text='Удалить', command=remove).grid(row=2, column=2, padx=(8, 0))
    ttk.Label(frame, text='Название набора').grid(row=3, column=0, sticky='w')
    ttk.Entry(frame, textvariable=name).grid(row=3, column=1, columnspan=2, sticky='ew', pady=5)
    for row, (key, title) in enumerate([('bundle_id', 'Bundle ID'), ('team_id', 'Team ID'), ('aps_environment', 'APNs окружение')], start=4):
        ttk.Label(frame, text=title).grid(row=row, column=0, sticky='w', padx=(0, 12))
        widget = ttk.Combobox(frame, textvariable=fields[key], values=['production', 'development'], state='readonly') if key == 'aps_environment' else ttk.Entry(frame, textvariable=fields[key])
        widget.grid(row=row, column=1, columnspan=2, sticky='ew', pady=5)
    buttons = ttk.Frame(frame)
    buttons.grid(row=7, column=0, columnspan=3, sticky='w', pady=(10, 16))
    ttk.Button(buttons, text='Сохранить набор', command=save).pack(side='left')
    ttk.Button(buttons, text='Заполнить из .mobileprovision', command=import_profile).pack(side='left', padx=10)
    ttk.Label(frame, text='Исходный IPA').grid(row=8, column=0, sticky='w')
    ttk.Entry(frame, textvariable=source_path).grid(row=8, column=1, sticky='ew')
    ttk.Button(frame, text='Выбрать…', command=choose_ipa).grid(row=8, column=2, padx=(8, 0))
    prepare_button = ttk.Button(frame, text='Подготовить отдельный IPA', command=prepare_clicked)
    prepare_button.grid(row=9, column=0, columnspan=3, sticky='ew', pady=16)
    ttk.Label(frame, textvariable=status, wraplength=650).grid(row=10, column=0, columnspan=3, sticky='w')
    ttk.Label(frame, text='Скрипт не подписывает приложение и не создаёт APNs-доступ.\nНовый Bundle ID означает отдельную установку и обычно повторный вход.\nНаборы хранятся локально; P12, пароли и UDID не сохраняются.', wraplength=650).grid(row=11, column=0, columnspan=3, sticky='w', pady=(16, 0))
    refresh_names()
    if profiles:
        selected.set('Folzy' if 'Folzy' in profiles else sorted(profiles)[0])
        choose_preset()
    else:
        show_config(DEFAULT_PROFILE)
    root.protocol('WM_DELETE_WINDOW', close)
    root.after(150, poll)
    root.mainloop()


def main():
    if len(sys.argv) == 1:
        launch_gui()
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    args = parser.parse_args()
    bundle_id = prepare(args.input, args.output, json.loads(args.config.read_text()))
    print(f'Prepared {args.output.name}: {bundle_id}. Final ESign signing is REQUIRED.')


if __name__ == '__main__':
    main()
