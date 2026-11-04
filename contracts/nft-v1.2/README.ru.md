# NFT Collection v1.2 — протокол подтверждённого минта

Эта версия находится отдельно от `nft-v1.1`. Она предназначена для новой тестовой коллекции, администратором которой после проверки станет Auction Manager. GitHub-изменения не обновляют bytecode уже развёрнутой коллекции.

## Поток выпуска

1. Auction Manager вызывает `DeployNftV12`. Коллекция проверяет admin, следующий индекс и отсутствие уже существующей записи, сохраняет ожидаемый адрес NFT Item и отправляет deployment с `RichBounce`.
2. NFT Item проверяет отправителя-коллекцию и совпадение индекса с StateInit, сохраняет владельца и metadata content, затем отправляет `NftItemInitializedV12`.
3. Коллекция принимает callback только от детерминированного адреса NFT Item и только при совпадении `queryId`. Она сохраняет состояние `READY_FOR_MANAGER` и отправляет Auction Manager `NftItemDeploymentConfirmedV12`.
4. Auction Manager после обработки подтверждения отправляет `NftItemDeploymentAckV12`. Только после ACK запись ожидания удаляется.
5. Если deploy NFT Item bounced, коллекция переводит запись в `FAILED` и отправляет `NftItemDeploymentFailedV12`. Менеджер должен обработать ошибку и подтвердить её ACK.
6. Если callback от NFT Item не дошёл до коллекции, менеджер вызывает `RetryNftItemDeploymentNoticeV12`: коллекция просит NFT Item повторить callback. Исходный `queryId` хранится в самом NFT Item и проверяется при повторном запросе.
7. Если уведомление менеджеру bounced, запись остаётся в коллекции. Менеджер повторяет уведомление тем же вызовом `RetryNftItemDeploymentNoticeV12`.

Индексы не переиспользуются после неудачного deployment. Прямой batch mint в этой версии не предусмотрен.

## Статусы

- `0` — ждём инициализацию NFT Item;
- `1` — NFT Item инициализирован, ждём ACK от Auction Manager;
- `2` — deployment завершился bounce, ждём обработки ошибки и ACK.

Публичный getter `get_pending_nft_deployment(index)` позволяет проверить состояние и диагностировать незавершённую обработку.

## Развёртывание

Из корня репозитория после успешных сборки и тестов:

```sh
acton script scripts/deployCollectionV12.tolk --net testnet --tonconnect
```

Скрипт создаёт отдельную коллекцию v1.2 в TON Testnet с роялти 2% в пользу deployer-кошелька. Он не меняет старую коллекцию. Admin передаётся Auction Manager только после его реализации и полного тестирования.
