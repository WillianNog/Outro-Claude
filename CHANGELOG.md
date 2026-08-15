# Changelog — MetaFit

Registro enxuto de decisões e alterações. Mais recente primeiro. Ver `MetaFit/HANDOFF.md` para o estado atual completo do projeto.

## 2026-08-15 — Auditoria consolidada + correção em massa

Um workflow de agentes leu tudo que já tinha sido escrito sobre o projeto (auditoria, memória, mural, código, config), consolidou em um backlog único de 34 itens, e verificou cada um contra o código/Supabase reais — confirmando 45 itens e achando **15 erros novos** não documentados antes. A partir disso:

**Segurança**
- Descoberto que a chave do Supabase no histórico do Git (commit `2b6eec4`) não era uma "chave antiga" — é byte-a-byte idêntica à chave ativa em produção hoje.
- App trocado para usar a **publishable key** moderna (`sb_publishable_...`) em vez da anon key legada (formato JWT); GitHub Secret `SUPABASE_ANON_KEY` atualizado com o mesmo valor. Isso reduz o que builds futuros expõem, mas **não invalida** a chave legada já vazada — só o Willian pode desativá-la no painel do Supabase (Project Settings → API). Decisão pendente: limpar o histórico do Git (exige push forçado, não fiz sem confirmação explícita).
- Adicionado rate limiting (máx. 5 tentativas/minuto por usuário) na RPC `join_group_by_code`, que não tinha nenhuma proteção contra força-bruta do código de convite (4 caracteres, ~1,19M combinações).
- CI (`build-apk.yml`) passou a apagar keystore/`key.properties`/`supabase_config.dart` do workspace ao final do job (`if: always()`) — antes ficavam em texto puro no disco do runner até o job encerrar sozinho.
- Corrigido `applicationId`/`namespace` duplicado (`com.ativore.metafit.metafit` → `com.ativore.metafit`) no CI, no `setup.ps1` e no `build.gradle.kts` local — teria ficado permanentemente errado se publicado assim na Play Store.
- `.gitignore` corrigido: a regra específica de `key.properties` apontava para o caminho errado (faltava `/app/`).

**Banco de dados (Supabase, projeto `fvsynfsljatdbevbgmsk`)**
- 13 políticas RLS reescritas para envolver `auth.uid()` em `(select auth.uid())` (advisor de performance `auth_rls_initplan`, novo desde a última auditoria — antes só tinha sido rodado o advisor de segurança).
- `groups.name` ganhou `DEFAULT 'MetaFit'` (antes um resquício do rebrand deixava `'Flexão 3000'` como default).
- Adicionados índices que faltavam em 3 foreign keys (`group_members.user_id`, `groups.owner_id`, `profiles.active_group_id`) e chave primária na nova tabela `join_attempts`.

**App (`lib/main.dart`)**
- Os 5 blocos `catch (_) {}` que engoliam erro de rede em silêncio (`_loadEntries`, `_loadGroup`, `_loadRanking`, `_saveCloud`, `_editDay`) agora logam o erro e mostram feedback visível: um banner "não foi possível atualizar" com botão de retry para leituras, e uma fila de pendência com indicador "não sincronizado, toque para tentar de novo" no card "Hoje" para gravações.
- Corrigidos ~10 pontos onde um `setState()` rodava depois de um `await` sem checar `mounted` — risco real de crash ("setState() called after dispose()"), não só um erro engolido.
- `_loadRanking()` trocado de N+1 queries (uma por membro do grupo) para uma única query em lote.
- Canal Realtime ganhou filtro por `group_id` (antes recarregava o ranking a cada mudança em `entries` de QUALQUER grupo), debounce de 400ms, e callback de erro/status (antes uma falha no canal passava despercebida).
- `_deleteAccount()`: a checagem de "é dono do grupo?" usada no aviso de exclusão estava errada (`_players.isNotEmpty` é verdade pra qualquer membro, não só o dono) — corrigida para comparar com o `owner_id` real do grupo.
- `_signOut()` não tratava erro nenhum e era `void` (nem dava pra dar `await`/`catch` nela) — virou `Future<void>` com try/catch e feedback.
- Corrigido bug em que o modo local (sem conta) mostrava o total do Dashboard atualizando ao vivo, mas a aba Ranking ficava travada no valor de quando o app abriu.
- `_createGroup()` ganhou retry automático (até 3 tentativas) quando o código de convite sorteado colide com um já existente.
- `_joinGroup()` passou a diferenciar erro de servidor de erro de conexão, em vez de uma mensagem genérica pra tudo.
- `_loadLocal()` (dados locais em `shared_preferences`) ganhou validação — antes um JSON corrompido deixava o app preso no carregamento sem chance de recuperação.
- Removida uma função `_cardDeco()` duplicada (definida duas vezes com o mesmo corpo).
- `TextEditingController`s sem `dispose()` corrigidos (`_GroupSetupScreenState._codeCtrl` vazava a cada tela; o controller do diálogo de editar dia também não era descartado).
- `main()` ganhou uma guarda: se `supabase_config.dart` estiver ausente/mal preenchido, mostra uma tela de erro explicativa em vez de crashar cru na inicialização.

**Dependências**
- `mobile_scanner` `^6.0.2` → `^7.4.0`, `google_fonts` `^6.2.1` → `^8.2.1`, `flutter_lints` `^4.0.0` → `^6.0.0`. Validado com `flutter analyze` (0 problemas) e um build de debug completo — sem breaking changes na API do `MobileScanner` usada em `_ScanQrScreen`.
- CI ganhou um step `flutter analyze` como gate de qualidade antes do build de release.

**Documentação**
- `HANDOFF.md` e `README.md` reescritos — ainda descreviam uma versão pré-Supabase do app (plano de migrar para Firebase/Firestore, códigos `FLEX-XXXX`), incompatível com o código real há tempo.
- Mural (`mural-metafit.html`) atualizado: faltavam os nodes de "Esqueci minha senha" e "Excluir minha conta" (ambos já existem no app real); o achado sobre a chave do Supabase foi corrigido para dizer que é a chave ativa, não uma antiga.

**Adiado para uma próxima rodada (não implementado agora — risco/escopo maiores, merecem foco dedicado)**
- Recuperação de senha ponta a ponta: falta o deep link (`AndroidManifest.xml`) + tela de "definir nova senha"; hoje só o e-mail é disparado.
- Transferência de propriedade de grupo na exclusão de conta (hoje o grupo inteiro cascateia e some).
- Ícone/splash de marca (hoje são os padrões do `flutter create`).
- Monitoramento de erro em produção (Sentry/Crashlytics).
- Testes automatizados (pasta `test/` ainda não existe).
- Auditoria de acessibilidade.

**Itens que só o Willian pode resolver**
- Desativar/rotacionar a anon key legada no painel do Supabase.
- Backup pessoal do keystore de release (`C:\metafit-keystore\`) fora deste computador — hoje só existe aqui e no GitHub Secrets (que não dá pra ler de volta).
- Confirmar se "Confirm email" está ativo no Supabase Auth (não é verificável por ferramenta).
- Criar a conta de desenvolvedor no Google Play Console.
- Decidir sobre plano pago do Supabase (o free não tem backup point-in-time e pausa por inatividade).
- Nada deste commit foi enviado ao GitHub ainda — segue tudo local até o Willian pedir o push.

## Antes deste changelog existir

Sessão anterior (2026-08-14/15): rebrand completo de "Flexão 3000" para MetaFit; adição de QR code (gerar + escanear) pra entrar em grupo; correção de uma falha real de RLS (leitura vazava dados entre grupos diferentes); checklist técnico da Play Store fechado (assinatura de release, build AAB, exclusão de conta, política de privacidade, recuperação de senha inicial); toolchain Android local montado do zero num Windows sem nada instalado. Detalhes em `MetaFit/HANDOFF.md`.
