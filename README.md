# Beatriz Cordeiro — Agenda

App de agenda, clientes e caixa para a Beatriz Cordeiro Nail Designer.
Flutter (Android, iPhone e web) + Supabase.

## Abrir no celular
A versão web é publicada automaticamente no GitHub Pages a cada `git push` na branch `main`
(veja a aba **Actions**). No celular, abra o link e use **Adicionar à tela inicial**.

## Supabase
Os scripts ficam em `supabase/`:
- `schema.sql` — tabelas, segurança (RLS) e views de fechamento
- `recovery.sql` — recuperação de senha por palavra secreta
- `seed.sql` — serviços iniciais (opcional; o app já cadastra sozinho numa conta nova)

## Rodar no computador
```bash
flutter pub get
flutter run
```
