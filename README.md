# GameVault

Loja de Blox Fruits e Discord com lobby, catálogo PT/EN/ES, login Supabase, pedidos Pix e atendimento Tawk.to.

## 1. Configurar cadastro e login

1. Crie um projeto em [supabase.com](https://supabase.com/) e abra **SQL Editor**.
2. Copie e execute o conteúdo atualizado de `supabase-setup.sql` no SQL Editor. Ele cria perfis, catálogo com estoque (incluindo Conta Nitro de 3 meses com 14 boosts por R$ 14), pedidos e itens, funções atômicas de reserva/cancelamento e políticas RLS. Se já executou uma versão antiga, execute o arquivo atualizado inteiro novamente.
3. Em **Authentication > Providers**, habilite **Email**. Em produção, mantenha a confirmação de e-mail ligada e configure o SMTP para que os links de confirmação sejam entregues corretamente.
4. Em **Authentication > URL Configuration**, adicione o endereço publicado do site em **Site URL** e **Redirect URLs**.
5. Em **Project Settings > API**, copie a **Project URL** e a chave pública **anon/publishable** para `config.js`:

```js
window.GAMEVAULT_CONFIG = {
  supabaseUrl: "https://SEU-PROJETO.supabase.co",
  supabaseAnonKey: "SUA_CHAVE_PUBLICA_ANON",
  tawkPropertyId: "69e541ca3ca1cc1c339ffa48",
  tawkWidgetId: "1jmjoi093",
  pixKey: "14591182436",
  pixMerchantName: "NOME DO TITULAR",
  pixMerchantCity: "CIDADE"
};
```

A chave `anon`/`publishable` é destinada ao navegador e fica protegida pelas políticas RLS. **Nunca** use `service_role`, `secret` ou senha do banco em `config.js`.

Qualquer pessoa pode criar uma conta de cliente. O gatilho SQL marca `adryelteste@gmail.com` como `admin` e os demais como `customer`; a tela consulta esse papel protegido no banco. O administrador precisa se cadastrar com esse endereço e confirmar o e-mail se a confirmação estiver ligada. O endereço é comparado sem diferenciar maiúsculas/minúsculas.

## 2. Pedidos Pix e aprovação

O checkout exige login e cria o pedido no Supabase. Execute `supabase-setup.sql` atualizado antes de usar: sem a tabela `products` e a função `create_gamevault_order`, não há pedido real. Os preços são calculados no banco e o estoque é reservado atomicamente por 20 minutos; se o comprador cancelar ou o pedido expirar, o estoque retorna. A tela monta um BR Code Pix com valor e referência do pedido, gera o QR localmente no navegador e permite copiar o código ou a chave CPF.

Como a chave fornecida é um Pix estático, o banco não avisa automaticamente este site quando recebe um pagamento. O pedido fica **pendente** até você entrar com `adryelteste@gmail.com`, abrir **Entrar** e usar **Confirmar pagamento recebido**. Confira o crédito no extrato bancário antes de aprovar. Só então o site marca o pedido como pago, exibe os itens comprados e mostra o botão para abrir o chat Tawk.to.

Em `config.js`, `pixMerchantName` e `pixMerchantCity` estão vazios intencionalmente. Preencha o nome do titular reconhecido pelo banco para esse CPF e a cidade do titular (até 15 caracteres no BR Code), exatamente como aparecem nos dados Pix da conta. O checkout não reserva estoque até esses campos estarem configurados. Não compartilhe senha bancária ou código de autenticação.

Com a chave CPF sozinha, o Pix é estático e o site não recebe uma confirmação automática do banco. O chat Tawk só é liberado depois da aprovação manual. Para confirmação automática após o pagamento, será necessário usar um provedor de cobrança Pix que gere cobranças dinâmicas e envie webhook; o CPF não fornece essa API.

## 3. Conectar o Tawk.to

1. O widget que você enviou já está configurado em `config.js`: Property ID `69e541ca3ca1cc1c339ffa48` e Widget ID `1jmjoi093`.
2. Não cole o bloco `<script>` do Tawk novamente; o site já carrega o widget usando esses identificadores. Se trocar de widget, substitua esses dois valores em `config.js`.
3. O Tawk.to carrega um serviço externo e pode coletar dados de navegação; configure a política de privacidade/consentimento que se aplique ao seu público antes de publicar.

## 4. Testar e publicar

Para testar no computador, abra um terminal nesta pasta e execute:

```powershell
node preview-server.js
```

Acesse `http://127.0.0.1:4173`. O cadastro real só funciona depois de preencher `config.js`, executar o SQL e liberar a URL no Supabase.

### Publicação rápida pelo Netlify

1. Preencha `config.js` com a URL e chave pública do Supabase e confirme nome/cidade do recebedor Pix. Os IDs do Tawk já estão configurados.
2. Acesse [app.netlify.com/drop](https://app.netlify.com/drop) e entre/crie sua conta Netlify.
3. Arraste a pasta inteira do projeto para a área de publicação (ela contém `index.html`, `config.js` e `supabase-setup.sql`).
4. Abra o endereço `*.netlify.app` criado e teste cadastro, confirmação de e-mail, login, idioma e o chat.
5. Volte ao Supabase e cadastre o endereço Netlify em **Authentication > URL Configuration**. Se trocar o domínio, atualize também essa configuração.

`supabase-setup.sql` e `README.md` são arquivos de apoio; o site servido é formado por `index.html` e `config.js`. Pedidos e estoque ficam no Supabase. A confirmação Pix é manual; para automatizá-la, integre um provedor Pix com webhook. Configure também privacidade/consentimento para o serviço externo Tawk.to.
