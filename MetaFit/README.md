# MetaFit

App Android de desafio compartilhado de flexões entre amigos. Meta individual: 3.000 flexões até 31 de dezembro. Backend em Supabase (Postgres + Auth + Realtime + Edge Functions).

## Já implementado

- Cadastro/login por e-mail e senha (Supabase Auth), com opção "Usar sem conta" (modo 100% local).
- Recuperação de senha por e-mail (o link ainda não abre de volta no app — ver `HANDOFF.md`).
- Criar grupo ou entrar em um grupo existente por código (`META-XXXX`) ou escaneando um QR code pela câmera.
- Registro diário com atalhos +1, +5 e +10, e opção de desfazer.
- Meta anual, saldo restante e média diária necessária.
- Sequência (streak) de dias seguidos com medalhas.
- Histórico dos últimos 7 dias, com edição/remoção de qualquer dia.
- Totais por semana, mês e ano.
- Ranking do grupo em tempo real (Supabase Realtime), com fila local para reenviar quando uma gravação falha por falta de conexão.
- Exclusão de conta (Edge Function `delete-account`), com aviso quando o usuário é dono de um grupo.

## Rodar localmente

1. Instale Flutter, Android Studio/SDK e um JDK 17.
2. Copie `lib/supabase_config.dart.sample` para `lib/supabase_config.dart` e preencha `supabaseUrl`/`supabasePublishableKey` (pegue no painel do Supabase, projeto `fvsynfsljatdbevbgmsk` → Project Settings → API).
3. `flutter pub get`
4. `flutter run`

**No Windows**, se o caminho do projeto tiver acento (ex.: `Projeto Flexão`), o build nativo do Flutter/Android quebra — veja o workaround em `HANDOFF.md`.

## Gerar APK/AAB de release

O CI (`.github/workflows/build-apk.yml`) já faz isso a cada push em `main`, assinando com o keystore de release. Para gerar localmente:

```
flutter build apk --release
flutter build appbundle --release
```

O AAB (`build/app/outputs/bundle/release/app-release.aab`) é o formato exigido para publicar na Play Store.

Veja `HANDOFF.md` para arquitetura, o que ainda falta e decisões técnicas registradas.
