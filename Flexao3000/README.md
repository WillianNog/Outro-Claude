# Flexão 3000

Aplicativo Android de desafio compartilhado de flexões. A meta individual é de 3.000 flexões até 31 de dezembro.

## Já implementado

- Boas-vindas com nome e ponto de entrada para login Google.
- Registro diário com atalhos +1, +5 e +10.
- Opção de desfazer uma flexão.
- Meta anual, saldo restante e média diária necessária.
- Sequência (streak) de dias seguidos com medalhas.
- Histórico dos últimos 7 dias, com edição/remoção de qualquer dia.
- Totais por semana, mês e ano.
- Ranking local inicial e fluxo de grupo por código, com botão de compartilhar.
- Persistência local: os registros ficam no aparelho ao fechar o app.

## Rodar e gerar APK

1. Instale Flutter, Android Studio e um JDK.
2. Na pasta do projeto, rode `flutter create .` e `flutter pub get`.
3. Teste com `flutter run`.
4. Gere o APK com `flutter build apk --release`.

O arquivo final será criado em `build/app/outputs/flutter-apk/app-release.apk`.

## Login Google e ranking em tempo real

Para ativar a versão compartilhada de verdade, crie um projeto Firebase e habilite:

1. Authentication > Google.
2. Cloud Firestore.
3. Um app Android com o identificador que será definido quando o Flutter criar a pasta `android`.

Depois, inclua o arquivo `google-services.json` no app Android. Ele contém configurações exclusivas do seu projeto e não deve ser enviado publicamente.

Veja `HANDOFF.md` para o estado detalhado do projeto e os próximos passos.
