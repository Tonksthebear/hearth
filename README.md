# Hearth

Self-hosted household health app — meals, training, habits, and an optional AI coach.

Hearth is designed to run on **your** machine or server. You keep your data; the project is not a multi-tenant SaaS.

## Stack

Rails **8.1** Hotwire defaults (HTML-first):

| Layer | Choice |
|-------|--------|
| Framework | Rails 8.1 |
| Assets | Propshaft + importmap (**no Node build** for JS) |
| CSS | Tailwind CSS (`tailwindcss-rails`) |
| Interactivity | Turbo + Stimulus |
| DB (default) | SQLite |
| Jobs / cache / cable | Solid Queue, Solid Cache, Solid Cable |
| Deploy | Kamal + Docker + Thruster |

## Status

Scaffold only. Domain models (households, recipes, workout logs, HealthKit sync client, coach) come next.

Related content vault (Blueprint-inspired catalog drafts): separate `Meals` project.

## Development

```bash
bin/setup
bin/dev
```

Then open [http://localhost:3000](http://localhost:3000).

## License

[O'Saasy License](LICENSE) — free to use and self-host; no competing hosted SaaS that resells the product’s core functionality.
