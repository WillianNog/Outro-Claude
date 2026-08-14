# Handoff - Flexão 3000

## Objetivo

Aplicativo Android compartilhado para um desafio anual de 3.000 flexões entre amigos. Cada participante registra as flexões do dia; o grupo vê ranking e progresso.

## Estado atual

O projeto é um app Flutter de interface clara/clean. O código principal está em `lib/main.dart`.

Funcionalidades já implementadas localmente:

- Tela de boas-vindas com campo de nome.
- Botão visual de login Google e alternativa de uso sem login.
- Meta individual de 3.000 flexões até 31 de dezembro.
- Registro de flexões por dia: botões +1, +5 e +10.
- Ação para desfazer uma flexão.
- Progresso total, quantidade que falta e média diária necessária.
- Sequência (streak) de dias seguidos com medalhas (⚡ 🥉 🥈 🥇 🏆).
- Histórico dos últimos 7 dias com gráfico simples.
- Edição e remoção do registro de qualquer dia (toque em uma barra do histórico ou use "Editar outro dia" para escolher a data pelo calendário).
- Totais por período (semana / mês / ano) na tela de histórico.
- Ranking local de demonstração: usuário e "Seu amigo" (29 no dia).
- Grupo com código de demonstração `FLEX-2026`, tela de entrar/convidar e botão de compartilhar o código (via `share_plus`).
- Persistência local usando `shared_preferences`; registros sobrevivem ao fechamento do app.

Dados iniciais definidos no app:

- Usuário: Willian (editável na tela inicial).
- Registro inicial local: 25 flexões na data em que o app for aberto pela primeira vez.
- Amigo no ranking de demonstração: 29 flexões hoje.

## O que falta para ficar pronto para amigos usarem

### 1. Preparar e gerar o APK

O projeto ainda não tem as pastas Android porque o Flutter não concluiu a primeira configuração neste computador.

No ambiente com Flutter + Android Studio/JDK instalados:

```powershell
flutter create --project-name flexao_3000 --org com.ativore.flexao .
flutter pub get
flutter run
flutter build apk --release
```

APK esperado: `build/app/outputs/flutter-apk/app-release.apk`.

### 2. Login Google real

Criar projeto no Firebase, registrar o aplicativo Android, habilitar **Authentication > Google** e baixar `google-services.json`. Esse arquivo deve ficar em `android/app/` e não deve ser publicado.

Adicionar dependências recomendadas:

```yaml
firebase_core: ^3.0.0
firebase_auth: ^5.0.0
google_sign_in: ^6.0.0
cloud_firestore: ^5.0.0
```

O botão "Continuar com Google" atualmente apenas entra no fluxo local. Substituir por `GoogleSignIn` + `FirebaseAuth`.

### 3. Sincronização do grupo

Migrar dados locais para Cloud Firestore. Modelo sugerido:

```text
users/{uid}
  displayName, photoUrl, activeGroupId

groups/{groupId}
  name, inviteCode, ownerId, createdAt

groups/{groupId}/members/{uid}
  displayName, photoUrl, joinedAt

groups/{groupId}/entries/{uid_yyyy-MM-dd}
  uid, date, count, updatedAt
```

O ranking diário/semanal deve ser calculado a partir de `entries`, usando streams do Firestore. Validar nas regras que cada usuário apenas grava entradas com seu próprio `uid` e que só membros podem ler o grupo.

Quando isso existir, o ranking e os totais por período (já implementados localmente para o usuário atual) passam a valer para todos os membros do grupo, não só para os dados de demonstração do "Seu amigo".

### 4. Melhorias planejadas

- Nome/avatares reais no ranking (depende da sincronização do grupo, item 3).
- Notificações de lembrete e quando alguém assume liderança.
- Tela de perfil.
- Ícone/splash personalizados e assinatura do APK de release.

Concluído nesta rodada: streaks/medalhas, edição/remoção de um dia específico, totais por semana/mês/ano e convite via compartilhar código (ainda falta compartilhar link direto, que depende do item 3 para existir um link de fato).

## Observações técnicas

- `shared_preferences` guarda somente a versão local atual no mapa JSON `dailyPushupsV2`.
- O total deve continuar sendo calculado a partir dos registros diários, nunca por um contador separado.
- Acentos foram restaurados no código (o arquivo é UTF-8); o problema de codificação era específico do terminal Windows usado antes, não do Flutter.
- `share_plus` foi adicionado ao `pubspec.yaml` para o botão de compartilhar código do grupo; `flutter_localizations` foi adicionado para o seletor de data (`showDatePicker`) aparecer em pt-BR. Rode `flutter pub get` após atualizar.
- A pré-visualização anterior está em `preview.svg`; ela é somente uma referência visual e pode ser atualizada para acompanhar as telas atuais.

## Arquivos importantes

- `lib/main.dart`: toda a interface e lógica atual.
- `pubspec.yaml`: dependências Flutter.
- `README.md`: guia curto de execução.
- `preview.svg`: mockup da tela inicial.
