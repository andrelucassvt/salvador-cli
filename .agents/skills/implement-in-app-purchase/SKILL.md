---
name: implement-in-app-purchase
description: "Implements In-App Purchase (consumable, non-consumable, or subscription) following the project architecture. Asks whether there is a backend server, then generates the complete implementation: InAppPurchaseService, Cubit, State, View, DI registration, and purchase verification flow (local storage via StorageService OR backend endpoint call). Use whenever adding purchases, subscriptions, paywall, or premium features to the app, integrating App Store or Google Play billing, verifying receipts, or restoring purchases. Activate even when the user says 'make the app paid', 'add a paywall', 'implement premium', 'add a subscription plan', 'unlock premium features', 'add a pro version', or 'monetize the app' without explicitly mentioning InAppPurchase, StoreKit, or Google Play Billing."
---

# Implement In-App Purchase — Flutter

Implementa o fluxo completo de In-App Purchase seguindo a arquitetura do projeto.

## Leitura Rápida

- **Passo 1 obrigatório**: faça todas as perguntas em uma única mensagem e aguarde as respostas antes de gerar qualquer código.
- **Regra de ouro**: comprar é assíncrono — `buy()` apenas dispara a compra; o resultado SEMPRE chega pelo `purchaseStream` e é processado em um único lugar: `_processPurchaseUpdates` no Cubit.
- **Único ponto que muda entre os modos**: a implementação de `_verifyAndComplete()`. Sem back-end ela verifica localmente e salva no `StorageService`; com back-end ela chama `POST /purchases/verify`. Service, Cubit, State e View são idênticos no resto.
- **`completePurchase()` só após verificação bem-sucedida** — nunca antes.
- **Verificação por tipo**: compras únicas (consumível E não-consumível) usam `verifyPurchase`; SOMENTE assinatura usa `verifySubscription`.
- **Cubit**: cancele a subscription do stream no `close()` — nunca deixe o stream vazar.
- **Apple Guideline 3.1.2(c)**: paywall com assinatura DEVE exibir links de Termos de Uso (EULA) e Política de Privacidade, e um botão "Restaurar compras".
- **Segurança**: nunca desbloqueie conteúdo premium confiando apenas no client-side.

---

## Passo 1 — Perguntas obrigatórias (uma única mensagem)

Antes de gerar qualquer código, faça TODAS as perguntas abaixo de uma vez — use a ferramenta de perguntas da plataforma se existir (ex.: `AskUserQuestion`); senão, liste-as claramente e aguarde a resposta:

```
1. O app tem back-end próprio?
   - SIM → o servidor valida e registra as compras (modo 🅱)
   - NÃO → verificação 100% local no dispositivo (modo 🅰)

2. Quais tipos de produto? (pode marcar mais de um)
   - [ ] Consumível (ex: pacote de créditos)
   - [ ] Não-consumível permanente (ex: remover anúncios)
   - [ ] Assinatura (ex: plano mensal/anual)

3. Quais são os IDs dos produtos cadastrados nas lojas, por tipo?
   (App Store Connect e Google Play Console) Ex: "coins_100", "remove_ads", "premium_monthly"

4. Qual é o nome da feature/tela? Ex: "purchase", "paywall", "premium"

5. Se houver assinatura: quais as URLs de Termos de Uso e Política de Privacidade?
   (obrigatórias no paywall — Apple Guideline 3.1.2(c); use placeholder se ainda não existirem)
```

Guarde as respostas — elas definem os Sets de IDs, o modo de verificação e o nome dos arquivos.

---

## Passo 2 — Dependências (pubspec.yaml)

```yaml
dependencies:
  in_app_purchase: ^3.x.x
  url_launcher: ^6.x.x           # links de Termos/Privacidade no paywall
  verify_local_purchase: ^x.x.x  # SOMENTE no modo 🅰 (sem back-end)
```

---

## Passo 3 — Fluxo único com um ponto de variação

O fluxo é o mesmo nos dois modos. A verificação é o único ponto que muda:

```
View ──ação──▶ Cubit ──buy()──▶ InAppPurchaseService ──▶ App Store / Google Play
                 ▲                                                │
                 └───────────── purchaseStream ◀──────────────────┘
                 │
   _processPurchaseUpdates  (Cubit — idêntico nos dois modos)
                 │
   _verifyAndComplete(purchase)   ◀── ÚNICO ponto que muda
        ├─ 🅰 SEM back-end: VerifyLocalPurchase + StorageService (dentro do Service)
        └─ 🅱 COM back-end: PurchaseRepository → POST /purchases/verify
```

### Método correto por tipo de produto

| Tipo | Compra | Token | Verificação |
|---|---|---|---|
| Consumível | `buyConsumable` | `getOneTimePurchaseToken` | `verifyPurchase` |
| Não-consumível | `buyNonConsumable` | `getOneTimePurchaseToken` | `verifyPurchase` |
| Assinatura | `buyNonConsumable` | `getSubscriptionToken` | `verifySubscription` |

> `buyNonConsumable` também é o método correto para assinaturas — é assim que o plugin `in_app_purchase` funciona. O que diferencia assinatura é a verificação, nunca a compra.

---

## Passo 4 — Templates

### InAppPurchaseService (comum aos dois modos)

`lib/common/services/in_app_purchase/in_app_purchase_service.dart`

```dart
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

class InAppPurchaseService {
  // Preencha com as respostas do Passo 1. Sets vazios são permitidos.
  static const consumableIds = <String>{'coins_100'};
  static const nonConsumableIds = <String>{'remove_ads'};
  static const subscriptionIds = <String>{'premium_monthly'};

  static Set<String> get allIds =>
      {...consumableIds, ...nonConsumableIds, ...subscriptionIds};

  final InAppPurchase _iap = InAppPurchase.instance;

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  bool isSubscription(String productId) => subscriptionIds.contains(productId);

  Future<List<ProductDetails>> loadProducts() async {
    if (!await _iap.isAvailable()) {
      throw StateError('Loja indisponível neste dispositivo');
    }
    final response = await _iap.queryProductDetails(allIds);
    return response.productDetails;
  }

  Future<void> buy(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    return consumableIds.contains(product.id)
        ? _iap.buyConsumable(purchaseParam: param)
        : _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}
```

### Modo 🅰 (sem back-end) — adições no Service

Injete `StorageService` via construtor e adicione:

```dart
import 'package:verify_local_purchase/verify_local_purchase.dart';

Future<bool> verifyAndComplete(PurchaseDetails purchase) async {
  final isSub = isSubscription(purchase.productID);
  final token = isSub
      ? getSubscriptionToken(purchase)
      : getOneTimePurchaseToken(purchase);

  final verifier = VerifyLocalPurchase();
  final isValid = isSub
      ? await verifier.verifySubscription(token)
      : await verifier.verifyPurchase(token);

  if (isValid) {
    await _storage.setString(
      'purchase_receipt_${purchase.productID}',
      purchase.verificationData.localVerificationData,
    );
    await _storage.setString(
      'purchase_source_${purchase.productID}',
      purchase.verificationData.source, // "app_store" | "google_play"
    );
    await _iap.completePurchase(purchase);
  }
  return isValid;
}

Future<bool> isPurchased(String productId) async =>
    await _storage.getString('purchase_receipt_$productId') != null;
```

Use SEMPRE as chaves `purchase_receipt_<productId>` e `purchase_source_<productId>` — nenhuma outra variação.

### Modo 🅱 (com back-end) — arquivos adicionais

```
lib/domain/interfaces/purchase_repository.dart
lib/data/datasources/purchase_remote_datasource.dart
lib/data/repositories/purchase_repository_impl.dart
```

```dart
abstract class PurchaseRepository {
  /// Envia dados de verificação ao back-end e retorna se a compra é válida
  Future<Result<bool>> verifyPurchaseOnServer({
    required String productId,
    required String serverVerificationData,
    required String localVerificationData,
    required String source,
  });
}
```

Payload do `POST /purchases/verify`:

```json
{
  "product_id": "<purchase.productID>",
  "verification_data": "<purchase.verificationData.serverVerificationData>",
  "local_verification_data": "<purchase.verificationData.localVerificationData>",
  "source": "app_store | google_play"
}
```

No modo 🅱 o Service NÃO salva nada localmente e NÃO usa `verify_local_purchase` — a verificação inteira é responsabilidade do servidor.

### PurchaseState

```dart
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

@immutable
sealed class PurchaseState {
  const PurchaseState();
}

final class PurchaseInitial extends PurchaseState {
  const PurchaseInitial();
}

final class PurchaseLoading extends PurchaseState {
  const PurchaseLoading();
}

final class PurchaseLoaded extends PurchaseState {
  const PurchaseLoaded(this.products);
  final List<ProductDetails> products; // produtos E assinaturas juntos
}

final class PurchaseSuccess extends PurchaseState {
  const PurchaseSuccess(this.productId);
  final String productId;
}

final class PurchaseError extends PurchaseState {
  const PurchaseError(this.message);
  final String message;
}
```

### PurchaseCubit (idêntico nos dois modos, exceto `_verifyAndComplete`)

```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class PurchaseCubit extends Cubit<PurchaseState> {
  PurchaseCubit(this._service) : super(const PurchaseInitial()) {
    _subscription = _service.purchaseStream.listen(_processPurchaseUpdates);
  }

  final InAppPurchaseService _service;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = const [];

  Future<void> loadProducts() async {
    emit(const PurchaseLoading());
    try {
      _products = await _service.loadProducts();
      emit(PurchaseLoaded(_products));
    } catch (e) {
      emit(PurchaseError('Erro ao carregar produtos: $e'));
    }
  }

  Future<void> buy(ProductDetails product) async {
    emit(const PurchaseLoading());
    try {
      await _service.buy(product);
      // NÃO emita PurchaseSuccess aqui — o resultado chega pelo stream.
    } catch (e) {
      emit(PurchaseError('Erro ao iniciar compra: $e'));
    }
  }

  Future<void> restore() async {
    emit(const PurchaseLoading());
    await _service.restorePurchases();
    // O resultado chega pelo stream com PurchaseStatus.restored.
  }

  Future<void> _processPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          continue; // loja ainda processando — mantenha o Loading atual
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _service.completePurchase(purchase);
          }
          emit(PurchaseLoaded(_products)); // desistir não é erro — volte ao paywall
        case PurchaseStatus.error:
          emit(PurchaseError(purchase.error?.message ?? 'Erro na compra'));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final isValid = await _verifyAndComplete(purchase);
          isValid
              ? emit(PurchaseSuccess(purchase.productID))
              : emit(const PurchaseError('A compra não pôde ser verificada'));
      }
    }
  }

  // ÚNICO ponto que muda entre os modos — escolha UMA das duas versões:

  // 🅰 SEM back-end — o Service verifica, salva e completa:
  Future<bool> _verifyAndComplete(PurchaseDetails purchase) =>
      _service.verifyAndComplete(purchase);

  // 🅱 COM back-end — injete também PurchaseRepository no construtor:
  // Future<bool> _verifyAndComplete(PurchaseDetails purchase) async {
  //   final result = await _repository.verifyPurchaseOnServer(
  //     productId: purchase.productID,
  //     serverVerificationData: purchase.verificationData.serverVerificationData,
  //     localVerificationData: purchase.verificationData.localVerificationData,
  //     source: purchase.verificationData.source,
  //   );
  //   final isValid = result.when(ok: (value) => value, error: (_) => false);
  //   if (isValid) await _service.completePurchase(purchase);
  //   return isValid;
  // }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
```

> No modo 🅱, não use callback `async` dentro de `result.when` — extraia o valor primeiro (como acima) para garantir que o `completePurchase` seja aguardado.

### View (paywall) — requisitos

- `SafeArea` no conteúdo principal; `BlocBuilder` tratando TODOS os estados do sealed class
- `_cubit.loadProducts()` no `initState()`; `_cubit.close()` no `dispose()`
- Textos via `context.l10n.<chave>` — zero strings hardcoded; adicione as chaves nos ARB (`app_en.arb` e `app_pt.arb`)
- Botão **"Restaurar compras"** chamando `_cubit.restore()` (obrigatório para não-consumíveis e assinaturas — a Apple rejeita paywall sem restauração)
- Se houver assinatura, links de **Termos de Uso** e **Política de Privacidade** (Apple Guideline 3.1.2(c)):

```dart
import 'package:url_launcher/url_launcher.dart';

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    TextButton(
      onPressed: () => launchUrl(
        Uri.parse('https://sua-url/termos'),
        mode: LaunchMode.externalApplication,
      ),
      child: Text(l10n.premiumTermsOfUse),
    ),
    Text('·', style: theme.textTheme.bodySmall),
    TextButton(
      onPressed: () => launchUrl(
        Uri.parse('https://sua-url/privacidade'),
        mode: LaunchMode.externalApplication,
      ),
      child: Text(l10n.premiumPrivacyPolicy),
    ),
  ],
),
```

### DI (app_injector.dart) e inicialização

```dart
// 🅰 sem back-end:
inject.registerLazySingleton<InAppPurchaseService>(
  () => InAppPurchaseService(inject.get<StorageService>()),
);

// 🅱 com back-end (Service sem StorageService):
inject.registerLazySingleton<InAppPurchaseService>(InAppPurchaseService.new);
inject.registerLazySingleton<PurchaseRemoteDataSource>(/* ... */);
inject.registerLazySingleton<PurchaseRepository>(/* ... */);

// Ambos:
inject.registerFactory<PurchaseCubit>(() => PurchaseCubit(inject.get()));
```

No modo 🅰, inicialize o verificador no `AppInitializer`, ANTES de `setupDependencies`:

```dart
VerifyLocalPurchase.initialize(
  VerifyPurchaseConfig(
    appleConfig: AppleConfig(
      bundleId: 'com.example.app',
      issuerId: 'your-issuer-id',
      keyId: 'your-key-id',
      privateKey: '-----BEGIN PRIVATE KEY-----...',
      useSandbox: flavor != AppFlavor.production,
    ),
    googlePlayConfig: GooglePlayConfig(
      packageName: 'com.example.app',
      serviceAccountJson: '{"type":"service_account", ...}',
    ),
  ),
);
```

---

## Passo 5 — Como o app sabe que o usuário é premium

Implementar a compra não basta — defina também a checagem de acesso:

- **🅰 Sem back-end**: use `service.isPurchased(productId)` (lê o `StorageService`). Para **assinaturas**, revalide com `verifySubscription` na inicialização do app — o receipt salvo localmente não expira sozinho quando a assinatura é cancelada.
- **🅱 Com back-end**: consulte um endpoint de status (ex.: `GET /purchases/status`) — nunca decida premium só pelo que está no dispositivo.
- **Reinstalação/troca de aparelho**: as compras não estão mais no dispositivo — o botão "Restaurar compras" reaciona o fluxo via `PurchaseStatus.restored`.

---

## Passo 6 — Checklist final

Os templates acima já garantem o fluxo; confira apenas o que depende do contexto do projeto:

- [ ] Sets de IDs preenchidos com os IDs REAIS informados no Passo 1
- [ ] `_verifyAndComplete` implementado na versão do modo escolhido (🅰 ou 🅱) — nunca as duas
- [ ] Rota adicionada em `app_routes.dart` e `app_router.dart`
- [ ] Chaves de l10n criadas nos ARB (incluindo `premiumTermsOfUse` e `premiumPrivacyPolicy` se houver assinatura)
- [ ] 🅰: placeholders de credenciais substituídos (`bundleId`, `issuerId`, `keyId`, `privateKey`, `serviceAccountJson`)
- [ ] `flutter analyze` sem erros

Ao concluir, informe ao usuário o que ele deve testar manualmente:

- Compra de cada tipo de produto com conta sandbox (Sandbox Tester na App Store / testador de licença no Google Play)
- Cancelar a compra no diálogo da loja → tela volta ao paywall sem erro
- "Restaurar compras" após reinstalar o app
- Links de Termos e Privacidade abrindo no navegador externo

---

## Segurança (avisar sempre)

> ⚠️ **Nunca confie apenas na validação client-side para desbloquear conteúdo premium.**
> - **🅰**: o `verify_local_purchase` mitiga fraudes simples, mas as credenciais (chave `.p8`, service account) ficam embutidas no app e podem ser extraídas — trate como proteção razoável, não como garantia, e considere migrar para validação server-side.
> - **🅱**: conceda acesso premium SOMENTE após o servidor confirmar — nunca com base apenas no `purchaseStream`.

---

## Anti-patterns

- ❌ Emitir `PurchaseSuccess` direto no `buy()` — o resultado vem pelo stream
- ❌ Chamar `completePurchase()` antes da verificação
- ❌ Ignorar `PurchaseStatus.canceled` — a tela fica em Loading para sempre
- ❌ Criar DataSource/Repository no modo 🅰, ou usar `verify_local_purchase` no modo 🅱
- ❌ Acessar `InAppPurchaseService` diretamente da View — sempre via Cubit
- ❌ Usar `SharedPreferences` direto — sempre `StorageService`
- ❌ Inventar chaves de storage — apenas `purchase_receipt_<id>` e `purchase_source_<id>`
- ❌ Verificar assinatura com `verifyPurchase` ou não-consumível com `verifySubscription`

---

**Última atualização**: 25 de agosto de 2026
