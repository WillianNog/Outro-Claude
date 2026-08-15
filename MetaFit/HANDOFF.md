# Handoff — MetaFit

## Objetivo

App Android compartilhado para um desafio anual de 3.000 flexões entre amigos. Cada participante registra as flexões do dia; o grupo vê ranking e progresso em tempo real.

## Arquitetura atual

Backend real em **Supabase** (não Firebase — o plano antigo de migrar para Firestore foi abandonado e substituído por Supabase ainda nesta fase do projeto). Todo o código está em `lib/main.dart`.

- **Auth**: `supabase_flutter`, e-mail/senha. Recuperação de senha via `resetPasswordForEmail` (falta a tela que recebe o link — ver pendências).
- **Dados** (Postgres, projeto `fvsynfsljatdbevbgmsk`):
  - `profiles` (id, display_name, active_group_id)
  - `groups` (id, name, invite_code, owner_id)
  - `group_members` (group_id, user_id)
  - `entries` (user_id, date, count) — `count` tem `CHECK (count >= 0 and count <= 100000)`
- **RLS**: todas as tabelas restritas a membros do mesmo grupo (ou ao próprio registro). Ver policies `*_select`/`*_insert`/`*_update`/`*_delete` no dashboard.
- **RPC `join_group_by_code(p_code)`**: `SECURITY DEFINER`, é como um usuário entra num grupo pelo código sem já ser membro (RLS normal não permitiria o SELECT direto). Tem throttling (máx. 5 tentativas/minuto por usuário) contra força-bruta do código de convite.
- **Edge Function `delete-account`**: apaga a conta do usuário (cascata apaga também entries/membership; se o usuário for dono de um grupo, o grupo inteiro some — ver pendências).
- **Realtime**: canal Postgres Changes na tabela `entries`, filtrado por `group_id`, com debounce de 400ms.
- **QR code**: a aba "Grupo" mostra um QR (`qr_flutter`) com `metafit://join/META-XXXX`; "Entrar com código" tem um botão "Escanear QR" (`mobile_scanner`) que abre a câmera e já envia o código lido. A permissão de câmera é registrada automaticamente pelo próprio plugin no Android — não precisa editar o `AndroidManifest.xml` à mão para isso.

## Configuração local

`lib/supabase_config.dart` é gitignored — copie de `lib/supabase_config.dart.sample` e preencha com a **publishable key** (formato `sb_publishable_...`, não a anon key legada em formato JWT) do projeto no painel do Supabase.

## Pendências conhecidas (em ordem de impacto)

1. **Recuperação de senha incompleta.** `resetPasswordForEmail` é chamado sem `redirectTo`, e o app não tem nenhum deep link nem tela para receber a volta do e-mail. Falta: registrar um scheme customizado (ex. `metafit://reset-password`) no `AndroidManifest.xml`, escutar `onAuthStateChange` por `AuthChangeEvent.passwordRecovery`, e ter uma tela de "definir nova senha". Precisa testar de ponta a ponta com um e-mail real antes de confiar nisso.
2. **Exclusão de conta apaga o grupo inteiro se o usuário for dono, sem transferência.** Hoje `groups.owner_id` tem `ON DELETE CASCADE`, então o grupo (e a participação de todo mundo nele) desaparece junto, sem aviso prévio aos outros membros. O ideal é reatribuir a propriedade a outro membro em vez de deixar cascatear.
3. **Ícone e splash screen ainda são os padrões do `flutter create`.** Precisa gerar um ícone de marca (paleta azul `#2A6DF4`, sem verde) e configurar `flutter_launcher_icons`/`flutter_native_splash`.
4. **Sem monitoramento de erros em produção** (Crashlytics/Sentry). Hoje uma falha em produção não gera nenhum alerta para quem mantém o app.
5. **Sem testes automatizados.** `flutter_test` está nas dependências mas não há nada em `test/`.
6. **Acessibilidade não auditada** (contraste, leitor de tela, área de toque de botões só-ícone).

Itens 1 e 2 valem mais que os demais porque afetam dados/contas reais de usuários; 3–6 são qualidade/polimento.

## Decisões técnicas registradas

- `_daily` (mapa data→contagem) é sempre a fonte da verdade; o total é somado a partir dele, nunca um contador separado.
- Falhas de rede ao salvar (`_saveCloud`/edição de um dia) entram numa fila em memória (`_pendingSync`) e mostram um aviso "não sincronizado, toque para tentar de novo" no card "Hoje" — não existe fila persistida em disco ainda (se o app fechar com algo pendente, a marcação de pendência se perde, mas o dado local em `_daily` já foi atualizado no dispositivo).
- **No Windows**, se o caminho do projeto tiver acento (ex.: `C:\Projeto Flexão\...`), o toolchain nativo do Dart/CMake quebra ao compilar para Android, mesmo com `android.overridePathCheck=true` no `gradle.properties` (isso só contorna o check do lado Gradle/JVM, não o do Dart AOT/CMake). Workaround usado: copiar o projeto inteiro para um caminho sem acento (`C:\build-metafit\MetaFit`) e buildar de lá. O CI (GitHub Actions, Linux) não tem esse problema.
- O keystore de assinatura de release (`metafit-release.keystore`) fica fora do repositório e fora de qualquer caminho acentuado — é a única coisa que permite publicar atualizações na Play Store depois do primeiro upload; precisa de backup pessoal (fora deste computador) além da cópia em GitHub Secrets.

## Arquivos importantes

- `lib/main.dart`: toda a interface e lógica do app.
- `lib/supabase_config.dart.sample`: modelo de configuração local (copiar e preencher, nunca commitar o real).
- `pubspec.yaml`: dependências Flutter.
- `.github/workflows/build-apk.yml`: CI que builda APK+AAB assinados a cada push em `main`.
- `README.md`: guia curto de execução.
