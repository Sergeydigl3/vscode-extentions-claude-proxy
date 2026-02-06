# 🔌 VS Code Extension Gallery Proxy

Прокси для VS Code Marketplace на случай, если доступ к `marketplace.visualstudio.com` ограничен.

Состоит из двух частей:
- **Серверная** — Caddy как реверс-прокси к Microsoft Marketplace
- **Клиентская** — скрипт патча `product.json` на машине с VS Code

---

## 📡 Серверная часть (Caddy)

Установите Caddy на любой VPS с доступом к `marketplace.visualstudio.com`.

### Конфигурация

Замените `example.com` на ваш домен в `/etc/caddy/Caddyfile`:

```caddy
example.com {
	handle /vscode/gallery* {
		uri strip_prefix /vscode/gallery
		reverse_proxy https://marketplace.visualstudio.com {
			header_up Host marketplace.visualstudio.com
			header_up X-Market-Client-Id VSCode
		}
		rewrite * /_apis/public/gallery{uri}
	}

	handle /vscode/items* {
		uri strip_prefix /vscode/items
		reverse_proxy https://marketplace.visualstudio.com {
			header_up Host marketplace.visualstudio.com
		}
		rewrite * /items{uri}
	}

	handle /vscode/cache* {
		uri strip_prefix /vscode/cache
		reverse_proxy https://vscode.blob.core.windows.net {
			header_up Host vscode.blob.core.windows.net
		}
		rewrite * /gallery{uri}
	}

	handle /vscode/control* {
		uri strip_prefix /vscode/control
		reverse_proxy https://az764295.vo.msecnd.net {
			header_up Host az764295.vo.msecnd.net
		}
	}
}
```

```bash
sudo systemctl restart caddy
```

Caddy автоматически получит SSL-сертификат через Let's Encrypt.

---

## 💻 Клиентская часть

One-liner команды для патча VS Code. Замените `example.com` на домен вашего прокси.

### Windows (PowerShell)
```powershell
&([scriptblock]::Create((irm https://raw.githubusercontent.com/Sergeydigl3/vscode-extentions-claude-proxy/main/patch-vscode.ps1))) -Domain "example.com"
```

### Linux (Bash)

```bash
curl -fsSL https://raw.githubusercontent.com/Sergeydigl3/vscode-extentions-claude-proxy/main/patch-vscode.sh | bash -s -- example.com
```

---

## 🔄 Откат

Запустите скрипт повторно — он определит, что прокси уже установлен, и предложит восстановить оригинальные URL. Резервная копия `product.json` создаётся автоматически перед каждым изменением.

---

## 📝 Примечания

- После обновления VS Code файл `product.json` перезаписывается — нужно запустить скрипт заново
- На Linux скрипт запросит `sudo` автоматически, если нет прав на запись
- Caddy сам управляет SSL-сертификатами
- Прокси не модифицирует расширения — только проксирует трафик
- Оригинальное форматирование `product.json` сохраняется
