# Backlog da API — versão reduzida (guia de desenvolvimento)

> Esta é a versão **reduzida e focada na API** do backlog. O backlog completo (48 tarefas,
> processo BPMN inteiro) continua em `docs/backlog.md` e serve de contexto — aqui ficam só as
> **8 tarefas** necessárias para ter uma API de simulação funcionando de ponta a ponta.
>
> Público-alvo deste documento: **programadores iniciantes**. Cada tarefa está escrita como um
> guia: o que é, por que existe, o que você precisa entender antes, passo a passo, como testar
> e como saber que terminou. Leia a tarefa inteira antes de começar a codar.

---

## 1. Visão geral

### O que estamos construindo

Uma API HTTP (Node.js + Express) que recebe um pedido de crédito (valor, modalidade, score do
cliente, prazo) e devolve a simulação completa: parcelas pelos sistemas **Price** e **SAC**, com
**datas reais** de vencimento, **IOF** e **tarifa de cadastro**, e o **CET** (Custo Efetivo Total)
com o demonstrativo exigido pela Resolução CMN 4.881/2020. Cada simulação é **gravada** no banco
e pode ser consultada depois, de forma paginada.

### As 8 tarefas

| Tarefa | Entrega | Tipo |
|---|---|---|
| **T-01** | `GET /api/modalidades` — lista as modalidades de crédito disponíveis | Endpoint |
| **T-02** | Função de cálculo de parcelas — **Price** | Função pura |
| **T-03** | Função de cálculo de parcelas — **SAC** | Função pura |
| **T-04** | Cronograma de amortização com **datas reais** de vencimento | Função pura |
| **T-05** | Encargos e tributos — **IOF + tarifa de cadastro** | Função pura |
| **T-06** | **CET** (Res. 4.881) e **demonstrativo** na resposta | Função pura |
| **T-07** | `POST /api/operacoes` — recebe o pedido, simula e **grava** a operação (banco e repositório já prontos) | Endpoint + banco |
| **T-08** | `GET /api/operacoes` (paginado) e `GET /api/operacoes/:id` | Endpoint |

"Função pura" = uma função JavaScript que recebe parâmetros e devolve um resultado, sem tocar em
banco, rede ou data/hora do sistema. São fáceis de testar isoladamente.

### Ordem e paralelismo

```
T-00 Preparar o ambiente (todo mundo, antes de qualquer coisa)
 │
 ├─ T-01 modalidades ─────────────────────────────────────────────┐
 │                                                                 │
 ├─ T-02 Price ──┐                                                 │
 │               ├─ T-04 cronograma ── T-05 encargos ── T-06 CET ──┤
 ├─ T-03 SAC ────┘                                                 │
 │                                                                 ├── T-07 POST /operacoes ── T-08 GET /operacoes
 └─ T-07 Parte A (banco) — ENTREGUE pela equipe de banco ──────────┘
```

- **Podem começar juntas, em paralelo:** T-01, T-02, T-03. A Parte A da T-07 (banco) já foi
  entregue pela equipe de banco (`docs/backlog-db.md`, D-01/D-02/D-04); cada pessoa só precisa
  rodar o banco na própria máquina (ver T-07 Parte A).
- **T-04** precisa que T-02 **ou** T-03 esteja pronta (usa o formato de parcelas delas).
- **T-05** precisa da T-04 (usa os dias corridos). **T-06** precisa da T-04 e T-05.
- **T-07** precisa de tudo acima. **T-08** precisa da T-07.

### Decisões fechadas para esta versão

Não reabra estas decisões durante a implementação — se discordar, levante na reunião.

| Tema | Decisão |
|---|---|
| Stack | Node.js **20 LTS ou mais novo** (recomendado 22), Express 5 (já no repo), **MySQL 8** acessado com a biblioteca `mysql2`. Sem ORM, sem ferramenta de migrations: `db/schema.sql` (estrutura, 3 tabelas) e `db/seed.sql` (carga inicial), rodados com `npm run schema` e `npm run seed`. Ambos são mantidos pela **equipe de banco** (`docs/backlog-db.md`). |
| Modalidades | **6 modalidades PF com parcelas** (lista na T-01). Cheque especial e cartão rotativo ficam **fora** — o CET deles segue outro caminho (art. 6º da Res. 4.881) e não tem cronograma de parcelas. |
| Convenção de taxa | Taxa **efetiva mensal, capitalização composta** (mesma convenção da série do BCB, ver `docs/research_tabela-juros-brasil_20260831.md` §2.5). |
| Unidade da taxa | **Fora** de `src/lib/` (catálogo, entrada e saída da API) a taxa é em **porcentagem** (`1.85` = 1,85% a.m.). **Dentro** de `src/lib/` a taxa é sempre **decimal** (`0.0185`). A conversão (`/ 100`) acontece em um único lugar: o serviço da T-07. |
| Encargos | IOF e tarifa de cadastro são **pagos antecipadamente**: descontados do valor que o cliente recebe. Não são financiados junto com o principal. |
| Datas | Vencimento mensal **no mesmo dia** da liberação. Se o mês não tem esse dia → último dia do mês. Se cair em sábado/domingo → **próximo dia útil** (segunda). **Feriados são ignorados** (simplificação declarada). |
| CET | Fórmula da Res. CMN 4.881/2020 (dias corridos / 365), resolvida numericamente por **bisseção**. Saída em % ao ano com 2 casas decimais. |
| Score | Inteiro de **0 a 1000**, 5 faixas (A–E). Faixa E = pedido **recusado**. |
| Arredondamento | Valores monetários sempre com **2 casas** (`arredonda2`). Arredonda-se **parcela a parcela** e a **última parcela absorve a diferença de centavos** para o saldo fechar em zero. |
| Testes | Funções puras (T-02 a T-06) têm **testes automatizados** com `node:test` (nativo do Node, sem instalar nada), usando os valores de referência deste guia. Endpoints são testados **manualmente** no Postman. |
| Segurança | Sem autenticação, sem rate limit — projeto acadêmico. |

### Estrutura de pastas ao final

```
calculo-juros/
├─ index.js                      ← sobe o servidor (já existe)
├─ package.json                  ← "test" (T-02); "--env-file", "schema" e "seed" já existem (equipe de banco)
├─ .env                          ← senhas do banco — NUNCA vai para o git (você cria a partir do .env.example)
├─ .env.example                  ← modelo do .env (já existe)
├─ db/                           ← TUDO aqui é da equipe de banco (não mexer)
│  ├─ schema.sql                 ← cria o banco e as 3 tabelas: modalidades, faixas_juros, operacoes
│  ├─ seed.sql                   ← carga inicial: 6 modalidades + 30 faixas de juros
│  ├─ schema.js / seed.js        ← rodam os .sql: npm run schema / npm run seed
│  └─ reset.sql                  ← apaga o banco inteiro (cuidado)
└─ src/
   ├─ app.js                     ← Express, middlewares, tratador de erros (T-01)
   ├─ db.js                      ← conexão com o MySQL (já existe — equipe de banco)
   ├─ dados/                     ← "tabelas" estáticas: catálogo e parâmetros
   │  ├─ modalidades.js          (T-01)
   │  ├─ parametros.js           (T-05)
   │  └─ faixasRisco.js          (T-07)
   ├─ lib/                       ← funções puras de cálculo (+ seus testes)
   │  ├─ util.js                 (T-02)  arredonda2
   │  ├─ erros.js                (T-01)  classe ErroDeNegocio
   │  ├─ price.js  price.test.js (T-02)
   │  ├─ sac.js    sac.test.js   (T-03)
   │  ├─ datas.js  cronograma.js + testes (T-04)
   │  ├─ encargos.js + teste     (T-05)
   │  ├─ cet.js  demonstrativo.js + testes (T-06)
   │  └─ calculaParcela.js       ← legado, usado só por /api/juros; não mexer
   ├─ servicos/                  ← orquestração (junta as peças)
   │  ├─ validaEntrada.js        (T-07)
   │  ├─ taxa.js                 (T-07)
   │  └─ simulacao.js            (T-07)
   ├─ repositorios/              ← tudo que fala SQL fica aqui (já existe — equipe de banco)
   │  ├─ modalidades.js          listarModalidades, buscarModalidade (uso futuro)
   │  ├─ faixasJuros.js          listarFaixas, buscarFaixaPorScore (uso futuro)
   │  └─ operacoes.js            existeIdentificador, salvar, buscarPorId, listar (T-07 usa; T-08 usa)
   └─ routes/                    ← endpoints HTTP (só recebem, validam e respondem)
      ├─ index.js                ← registro central (já existe)
      ├─ health.js               ← já existe, já checa o banco
      ├─ juros.js                ← legado, não mexer
      ├─ modalidades.js          (T-01)
      └─ operacoes.js            (T-07, T-08)
```

Regra de ouro das camadas: **rota** não faz cálculo nem SQL; **serviço** não sabe o que é HTTP;
**lib** não sabe o que é banco. Se você está escrevendo `res.json` dentro de `src/lib`, algo
está no lugar errado.

### Formato padrão de erro

Toda resposta de erro da API tem este formato — sempre, em qualquer endpoint:

```json
{
  "erro": {
    "codigo": "DADOS_INVALIDOS",
    "mensagem": "Há campos inválidos na requisição",
    "detalhes": ["valor deve ser um número maior que zero", "score deve estar entre 0 e 1000"]
  }
}
```

`detalhes` é opcional. O catálogo completo de códigos está no **Anexo B**.

### Fluxo de trabalho no Git (vale para todas as tarefas)

1. `git checkout main` e `git pull` — comece sempre do código mais novo.
2. Crie uma branch com o nome da tarefa: `git checkout -b T-02-price`.
3. Faça commits pequenos e frequentes com mensagem descritiva: `git commit -m "T-02: função calculaPrice com decomposição juros/amortização"`.
4. `git push -u origin T-02-price` e abra um **Pull Request** para `main` no GitHub.
5. **Outra pessoa da equipe revisa** o PR (lê o código, roda `npm test`, testa no Postman se for endpoint). Só depois faz o merge.
6. Nunca dê `git push` direto na `main`.

### Definition of Done (o que "pronto" significa)

Uma tarefa só está pronta quando **todos** os itens valem:

- [ ] Todos os **critérios de aceite** da tarefa marcados.
- [ ] `npm test` passa (quando a tarefa tem testes).
- [ ] `npm run dev` sobe sem erro e `GET /api/health` responde.
- [ ] PR revisado e aprovado por outro membro.
- [ ] Nenhum `console.log` de depuração esquecido; nenhum arquivo de experimento commitado.

---

## T-00 — Preparar o ambiente (todos, antes de começar)

**Tempo estimado:** 30 min. **Depende de:** nada.

### Passo a passo

1. **Node.js.** Abra o terminal e rode `node -v`. Precisa mostrar `v20.x` ou mais novo (`v22.x`
   é o ideal). Se não tiver, instale a versão LTS em <https://nodejs.org>.
2. **Clonar o repositório** (se ainda não tem): `git clone https://github.com/gmelchert/calculo-juros-facul.git` e entre na pasta.
3. **Instalar dependências:** `npm install`. Isso lê o `package.json` e baixa o Express para `node_modules/`.
4. **Subir a API:** `npm run dev`. Deve aparecer `API rodando em http://localhost:3000`. O `dev`
   usa `node --watch`, que reinicia o servidor sozinho toda vez que você salva um arquivo.
5. **Postman.** Instale em <https://www.postman.com/downloads/>. Crie uma requisição `GET`
   para `http://localhost:3000/api/health`. Resposta esperada: status `200` e
   `{ "status": "ok", "mensagem": "API está ok" }`.
6. **Leia** `como-criar-endpoint.txt` e `src/routes/teste-exemplo.js` — é o padrão de rota do
   projeto e todas as tarefas de endpoint seguem ele.
7. **Git.** Confira `git config user.name` e `git config user.email`. Se estiverem vazios, configure.

### Dois conceitos que vão aparecer em todas as tarefas

**Módulos ES (import/export).** O projeto usa `"type": "module"` no `package.json`. Isso significa:
- Você importa com `import { funcao } from './arquivo.js'` — **sempre com a extensão `.js`** no
  caminho. Esquecer o `.js` dá o erro `Cannot find module`.
- Você exporta com `export function nome() {}` (vários por arquivo) ou `export default` (um por arquivo).

**Objetos como parâmetro.** As funções deste projeto recebem **um objeto** em vez de vários
parâmetros soltos: `calculaPrice({ valor: 10000, taxaMes: 0.02, prazoMeses: 12 })`. Assim a
ordem não importa e fica claro o que é cada número. Dentro da função, usa-se
*desestruturação*: `function calculaPrice({ valor, taxaMes, prazoMeses }) { ... }`.

---

## T-01 — Endpoint de modalidades de crédito

**Depende de:** T-00. **Pode ser feita em paralelo com:** T-02, T-03, T-07 Parte A.
**Arquivos:** cria `src/dados/modalidades.js`, `src/routes/modalidades.js`, `src/lib/erros.js`;
altera `src/routes/index.js`, `src/app.js`.

### O que é e por que existe

Um "catálogo" das modalidades de crédito que a API sabe simular. Quem for chamar a API precisa
saber quais códigos de modalidade existem (`CONSIGNADO_INSS`, `VEICULOS`...) e os limites de
cada uma (prazo mínimo e máximo, taxa). A T-07 vai usar esse mesmo catálogo para validar o pedido
e descobrir a taxa. Por isso o catálogo mora em `src/dados/` (compartilhado) e não dentro da rota.

Esta tarefa também introduz duas peças de infraestrutura que **todas** as outras usam: a classe
de erro `ErroDeNegocio` e o **tratador de erros** do Express. O código delas está pronto abaixo —
copie e entenda, não precisa inventar.

### Conceitos

- **Modalidade** = o "tipo" de crédito. Usamos a nomenclatura da série de taxas do Banco Central
  (arquivo `docs/bcb_taxas_juros_2026-08-11_a_2026-08-17.csv`, coluna `Modalidade`).
- **Taxa base** = a taxa mensal de partida da modalidade (política da nossa "instituição").
  O score do cliente vai **somar** um spread a ela (T-07).
- **Teto** = a taxa máxima permitida. Para o consignado INSS o teto é **regulatório** (CNPS,
  1,85% a.m. — valor provisório, ver §6 da pesquisa); para as demais é um teto de política nossa.
- Os valores de taxa abaixo são **provisórios, definidos pela equipe**. As medianas do BCB
  (que já embutem IOF, por isso são maiores) estão como referência. Mudar um número aqui **não
  exige mudar nenhum código de cálculo** — essa é a razão de existir um arquivo de dados.

### Passo a passo

**1. Crie o catálogo em `src/dados/modalidades.js`:**

```js
// Catálogo das modalidades de crédito que a API simula.
// Taxas em % ao mês (1.60 = 1,60% a.m.). Valores PROVISÓRIOS definidos pela equipe.
// Referência (mediana BCB 11–17/08/2026, já com IOF): INSS 1,83 | público 1,84 |
// privado 3,40 | veículos 1,77 | outros bens 2,53 | pessoal 5,25.
export const MODALIDADES = [
  {
    codigo: 'CREDITO_PESSOAL',
    nome: 'Crédito pessoal não consignado',
    modalidadeBcb: 'Crédito pessoal não consignado - Prefixado',
    publico: 'PF',
    regimeIndexacao: 'PREFIXADO',
    taxaBaseMes: 4.50,
    tetoTaxaMes: 12.00,
    prazoMinMeses: 3,
    prazoMaxMeses: 48,
    sistemas: ['PRICE', 'SAC'],
    descricao: 'Empréstimo sem garantia, pago em parcelas mensais.',
  },
  {
    codigo: 'CONSIGNADO_INSS',
    nome: 'Crédito pessoal consignado INSS',
    modalidadeBcb: 'Crédito pessoal consignado INSS - Prefixado',
    publico: 'PF',
    regimeIndexacao: 'PREFIXADO',
    taxaBaseMes: 1.60,
    tetoTaxaMes: 1.85, // teto regulatório CNPS — provisório, confirmar no DOU
    prazoMinMeses: 6,
    prazoMaxMeses: 84,
    sistemas: ['PRICE', 'SAC'],
    descricao: 'Parcelas descontadas diretamente do benefício do INSS.',
  },
  {
    codigo: 'CONSIGNADO_PUBLICO',
    nome: 'Crédito pessoal consignado público',
    modalidadeBcb: 'Crédito pessoal consignado público - Prefixado',
    publico: 'PF',
    regimeIndexacao: 'PREFIXADO',
    taxaBaseMes: 1.60,
    tetoTaxaMes: 2.50,
    prazoMinMeses: 6,
    prazoMaxMeses: 96,
    sistemas: ['PRICE', 'SAC'],
    descricao: 'Parcelas descontadas em folha de servidor público.',
  },
  {
    codigo: 'CONSIGNADO_PRIVADO',
    nome: 'Crédito pessoal consignado privado',
    modalidadeBcb: 'Crédito pessoal consignado privado - Prefixado',
    publico: 'PF',
    regimeIndexacao: 'PREFIXADO',
    taxaBaseMes: 2.80,
    tetoTaxaMes: 4.50,
    prazoMinMeses: 6,
    prazoMaxMeses: 48,
    sistemas: ['PRICE', 'SAC'],
    descricao: 'Parcelas descontadas em folha de empresa privada.',
  },
  {
    codigo: 'VEICULOS',
    nome: 'Aquisição de veículos',
    modalidadeBcb: 'Aquisição de veículos - Prefixado',
    publico: 'PF',
    regimeIndexacao: 'PREFIXADO',
    taxaBaseMes: 1.50,
    tetoTaxaMes: 3.00,
    prazoMinMeses: 12,
    prazoMaxMeses: 60,
    sistemas: ['PRICE', 'SAC'],
    descricao: 'Financiamento de veículo com o bem em garantia.',
  },
  {
    codigo: 'OUTROS_BENS',
    nome: 'Aquisição de outros bens',
    modalidadeBcb: 'Aquisição de outros bens - Prefixado',
    publico: 'PF',
    regimeIndexacao: 'PREFIXADO',
    taxaBaseMes: 2.20,
    tetoTaxaMes: 5.00,
    prazoMinMeses: 3,
    prazoMaxMeses: 36,
    sistemas: ['PRICE', 'SAC'],
    descricao: 'Financiamento de bens duráveis (eletrodomésticos, móveis etc.).',
  },
];

// Devolve a modalidade pelo código ou undefined se não existir.
export function buscaModalidade(codigo) {
  return MODALIDADES.find((m) => m.codigo === codigo);
}
```

**2. Crie a classe de erro em `src/lib/erros.js`** (copie como está):

```js
// Erro "esperado" da regra de negócio: sabe qual status HTTP e qual código devolver.
// Qualquer outro erro (bug, banco fora) vira 500 no tratador de erros do app.js.
export class ErroDeNegocio extends Error {
  constructor(status, codigo, mensagem, detalhes) {
    super(mensagem);
    this.status = status;      // ex.: 404, 400, 422
    this.codigo = codigo;      // ex.: 'MODALIDADE_NAO_ENCONTRADA'
    this.detalhes = detalhes;  // opcional: lista de strings
  }
}
```

**3. Adicione o tratador de erros em `src/app.js`**, depois do `app.use('/api', rotas)`:

```js
import { ErroDeNegocio } from './lib/erros.js';
// ...
app.use('/api', rotas);

// Tratador de erros: precisa ter EXATAMENTE 4 parâmetros para o Express reconhecer.
// No Express 5, erros lançados dentro das rotas (inclusive async) caem aqui sozinhos.
app.use((err, req, res, next) => {
  if (err instanceof ErroDeNegocio) {
    return res.status(err.status).json({
      erro: { codigo: err.codigo, mensagem: err.message, detalhes: err.detalhes },
    });
  }
  console.error(err); // erro inesperado: registra no terminal para investigar
  res.status(500).json({ erro: { codigo: 'ERRO_INTERNO', mensagem: 'Erro interno do servidor' } });
});
```

**4. Crie a rota em `src/routes/modalidades.js`:**

```js
import { Router } from 'express';
import { MODALIDADES, buscaModalidade } from '../dados/modalidades.js';
import { ErroDeNegocio } from '../lib/erros.js';

const router = Router();

// GET /api/modalidades — lista todas
router.get('/', (req, res) => {
  res.json({ total: MODALIDADES.length, itens: MODALIDADES });
});

// GET /api/modalidades/:codigo — uma só. ":codigo" é um parâmetro de rota: vem em req.params
router.get('/:codigo', (req, res) => {
  const modalidade = buscaModalidade(req.params.codigo);
  if (!modalidade) {
    throw new ErroDeNegocio(404, 'MODALIDADE_NAO_ENCONTRADA',
      `Modalidade "${req.params.codigo}" não existe`);
  }
  res.json(modalidade);
});

export default router;
```

**5. Registre em `src/routes/index.js`:** importe o arquivo e adicione
`router.use('/modalidades', modalidadesRoutes);` ao lado das rotas existentes.

**6. Teste** (abaixo) e abra o PR.

### Como testar (Postman)

| Requisição | Esperado |
|---|---|
| `GET http://localhost:3000/api/modalidades` | `200`, `total: 6`, `itens` com 6 objetos |
| `GET http://localhost:3000/api/modalidades/CONSIGNADO_INSS` | `200`, objeto com `tetoTaxaMes: 1.85` |
| `GET http://localhost:3000/api/modalidades/NAO_EXISTE` | `404`, `erro.codigo = "MODALIDADE_NAO_ENCONTRADA"` |
| `GET http://localhost:3000/api/health` | continua `200` |

### Critérios de aceite

- [ ] `GET /api/modalidades` devolve as 6 modalidades com todos os campos do catálogo.
- [ ] `GET /api/modalidades/:codigo` devolve 200 com a modalidade ou 404 no formato padrão de erro.
- [ ] `ErroDeNegocio` e o tratador de erros existem e funcionam (o 404 acima passa por eles).
- [ ] As rotas antigas (`/api/health`, `/api/juros/...`) continuam funcionando.

### Armadilhas comuns

- Esquecer o `.js` no final do `import` → `Cannot find module`.
- Registrar a rota em `index.js` com `/modalidade` (singular) e chamar `/modalidades` no Postman → 404 silencioso. Confira a URL completa.
- O tratador de erros **precisa** vir **depois** de `app.use('/api', rotas)` e ter 4 parâmetros (`err, req, res, next`), mesmo que `next` não seja usado.

---

## T-02 — Função de cálculo de parcelas — Price

**Depende de:** T-00. **Pode ser feita em paralelo com:** T-01, T-03.
**Arquivos:** cria `src/lib/util.js`, `src/lib/price.js`, `src/lib/price.test.js`; altera `package.json`.

### O que é e por que existe

No sistema **Price** (Tabela Price, ou Sistema Francês), todas as parcelas têm o **mesmo valor**.
É o sistema mais comum em crédito pessoal e financiamento de veículos. A função desta tarefa
recebe valor, taxa e prazo e devolve a lista de parcelas, cada uma decomposta em **juros** e
**amortização**, com o **saldo devedor** após o pagamento.

Essa decomposição é essencial para as tarefas seguintes: o IOF (T-05) incide sobre a
**amortização** de cada parcela, e o CET (T-06) precisa do **valor** de cada parcela.

### Conceitos

**A fórmula da parcela fixa (PMT):**

```
              i
PMT = PV × ───────────
           1 − (1+i)^(−n)
```

- `PV` = valor do empréstimo (principal). Ex.: 10.000
- `i` = taxa **decimal** ao mês. Ex.: 2% → `0.02`
- `n` = número de parcelas. Ex.: 12
- `(1+i)^(−n)` em JavaScript: `(1 + i) ** -n`

Para 10.000 a 2% em 12 meses: `PMT = 10000 × 0.02 / (1 − 1.02^−12) = 945,60`.

**Como cada parcela se decompõe (mês a mês):**

```
juros_k        = saldo_anterior × i          ← juros incidem sobre o que ainda se deve
amortizacao_k  = PMT − juros_k               ← o que sobra da parcela abate a dívida
saldo_k        = saldo_anterior − amortizacao_k
```

Na 1ª parcela: juros = 10000 × 0,02 = 200,00; amortização = 945,60 − 200,00 = 745,60;
saldo = 9.254,40. Na 2ª: juros = 9254,40 × 0,02 = 185,09; amortização = 760,51... Perceba que
os juros **caem** e a amortização **sobe** a cada mês, mas a soma é sempre 945,60.

**Arredondamento e a última parcela.** Cada valor é arredondado a 2 casas assim que é
calculado (é o que aparece no boleto). Isso gera diferenças de centavos ao longo dos meses.
Regra: na **última** parcela, a amortização é **o saldo que restou** (e não `PMT − juros`), para
o saldo final ser **exatamente 0,00**. Por isso a última parcela pode diferir alguns centavos
(no exemplo: 945,55 em vez de 945,60). Isso é normal e esperado.

### Contrato da função

```js
calculaPrice({ valor, taxaMes, prazoMeses })
// valor: number > 0        (ex.: 10000)
// taxaMes: number decimal  (ex.: 0.02 — NÃO 2)
// prazoMeses: inteiro ≥ 1  (ex.: 12)

// Retorna:
{
  sistema: 'PRICE',
  parcelaFixa: 945.60,
  parcelas: [
    { numero: 1, amortizacao: 745.60, juros: 200.00, valor: 945.60, saldoDevedor: 9254.40 },
    { numero: 2, amortizacao: 760.51, juros: 185.09, valor: 945.60, saldoDevedor: 8493.89 },
    // ...
    { numero: 12, amortizacao: 927.01, juros: 18.54, valor: 945.55, saldoDevedor: 0 },
  ],
  totalJuros: 1347.15,
  totalPago: 11347.15,
}
```

O formato de cada item de `parcelas` é **o contrato com a T-03, T-04, T-05 e T-06** — não
renomeie os campos.

### Passo a passo

**1. Crie `src/lib/util.js`** com a função de arredondamento que **todo o projeto** vai usar:

```js
// Arredonda para 2 casas decimais (centavos).
// O Number.EPSILON corrige casos como 1.005 que em ponto flutuante viram 1.00499999.
export function arredonda2(x) {
  return Math.round((x + Number.EPSILON) * 100) / 100;
}
```

Nunca use `toFixed(2)` para calcular — ele devolve **string**, não número.

**2. Crie `src/lib/price.js`** seguindo este roteiro (escreva você o código):

```js
import { arredonda2 } from './util.js';

export function calculaPrice({ valor, taxaMes, prazoMeses }) {
  // 1. Calcule a parcela fixa com a fórmula do PMT e arredonde com arredonda2.
  // 2. Crie um array vazio `parcelas` e uma variável `saldo` começando em `valor`.
  // 3. Faça um for de k = 1 até prazoMeses. Em cada volta:
  //    a. juros = arredonda2(saldo * taxaMes)
  //    b. se k < prazoMeses: amortizacao = arredonda2(parcelaFixa - juros)
  //       se k == prazoMeses (última): amortizacao = saldo   ← zera a dívida
  //    c. valorParcela = arredonda2(amortizacao + juros)
  //    d. saldo = arredonda2(saldo - amortizacao)
  //    e. dê push em parcelas de { numero: k, amortizacao, juros, valor: valorParcela, saldoDevedor: saldo }
  // 4. totalJuros = arredonda2 da soma de todos os `juros`; totalPago = arredonda2 da soma de todos os `valor`.
  //    (dica: use .reduce((soma, p) => soma + p.juros, 0))
  // 5. return { sistema: 'PRICE', parcelaFixa, parcelas, totalJuros, totalPago }
}
```

**3. Experimente no terminal** antes de escrever o teste. Crie um arquivo temporário
`experimenta.mjs` na raiz do projeto (**não commite**):

```js
import { calculaPrice } from './src/lib/price.js';
const r = calculaPrice({ valor: 10000, taxaMes: 0.02, prazoMeses: 12 });
console.log('parcelaFixa', r.parcelaFixa, 'totalJuros', r.totalJuros);
console.table(r.parcelas);
```

Rode `node experimenta.mjs` e compare com a tabela do **Anexo A.1**.

**4. Habilite os testes.** No `package.json`, dentro de `"scripts"`, adicione:
`"test": "node --test"`. O Node procura sozinho todos os arquivos `*.test.js`.

**5. Crie `src/lib/price.test.js`** (este é o **modelo** que as próximas tarefas vão copiar):

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculaPrice } from './price.js';

test('Price: 10.000 a 2% a.m. em 12 meses (cenário de referência)', () => {
  const r = calculaPrice({ valor: 10000, taxaMes: 0.02, prazoMeses: 12 });

  assert.equal(r.sistema, 'PRICE');
  assert.equal(r.parcelaFixa, 945.60);
  assert.equal(r.parcelas.length, 12);

  // 1ª parcela
  assert.equal(r.parcelas[0].juros, 200.00);
  assert.equal(r.parcelas[0].amortizacao, 745.60);
  assert.equal(r.parcelas[0].saldoDevedor, 9254.40);

  // última parcela zera o saldo e absorve os centavos
  assert.equal(r.parcelas[11].amortizacao, 927.01);
  assert.equal(r.parcelas[11].valor, 945.55);
  assert.equal(r.parcelas[11].saldoDevedor, 0);

  assert.equal(r.totalJuros, 1347.15);
  assert.equal(r.totalPago, 11347.15);
});

test('Price: 1 parcela = principal + juros de um mês', () => {
  const r = calculaPrice({ valor: 1000, taxaMes: 0.05, prazoMeses: 1 });
  assert.equal(r.parcelas[0].valor, 1050.00);
  assert.equal(r.parcelas[0].saldoDevedor, 0);
});
```

**6. Rode `npm test`.** Tudo verde → apague o `experimenta.mjs`, commite e abra o PR.

### Critérios de aceite

- [ ] `npm test` passa com os dois testes acima.
- [ ] A soma de todas as `amortizacao` é exatamente igual a `valor` (o saldo final é `0`).
- [ ] Todos os valores devolvidos são **números** com no máximo 2 casas decimais.
- [ ] `src/lib/util.js` existe e é a **única** implementação de arredondamento do projeto.

### Armadilhas comuns

- Passar `2` em vez de `0.02` como `taxaMes`. Dentro de `src/lib` a taxa é sempre decimal.
- Fazer `amortizacao = parcelaFixa - juros` também na última parcela → saldo final fica em ±0,05 em vez de 0.
- Somar os totais a partir dos valores **não** arredondados → `totalJuros` diverge em centavos do que está nas parcelas. Some os valores já arredondados que estão dentro de `parcelas`.
- `parcelaFixa: 945.6` no console é a mesma coisa que `945.60` — JavaScript não guarda zeros à direita.

---

## T-03 — Função de cálculo de parcelas — SAC

**Depende de:** T-02 (usa `arredonda2` e o mesmo formato de saída). **Pode ser feita em paralelo
com:** T-01. **Arquivos:** cria `src/lib/sac.js`, `src/lib/sac.test.js`.

> Se a T-02 ainda não foi mesclada, crie você o `src/lib/util.js` idêntico ao da T-02 — o git
> vai resolver sem conflito se o conteúdo for igual.

### O que é e por que existe

No **SAC** (Sistema de Amortização Constante) a **amortização** é a mesma todo mês e os juros
caem — logo as **parcelas são decrescentes**. É comum em financiamento imobiliário e é uma
alternativa ao Price que a API oferece em toda simulação. A saída tem **exatamente o mesmo
formato** da T-02, para que T-04, T-05 e T-06 funcionem com qualquer um dos dois sistemas sem
saber qual é.

### Conceitos

```
amortizacao    = PV / n                       ← fixa (arredondada a 2 casas)
juros_k        = saldo_anterior × i
parcela_k      = amortizacao + juros_k        ← decrescente
saldo_k        = saldo_anterior − amortizacao
```

Para 10.000 a 2% em 12 meses: amortização = 833,33. 1ª parcela = 833,33 + 200,00 = 1.033,33;
2ª = 833,33 + 183,33 = 1.016,66; ... 12ª = 833,37 + 16,67 = 850,04.

**Por que a última amortização é 833,37 e não 833,33?** Porque 833,33 × 12 = 9.999,96 — faltam
4 centavos. A mesma regra da T-02 vale: a **última** amortização é **o saldo que restou**.

### Contrato da função

```js
calculaSac({ valor, taxaMes, prazoMeses })   // mesmos parâmetros da T-02

// Retorna (mesmo formato da T-02, trocando parcelaFixa por amortizacaoBase):
{
  sistema: 'SAC',
  amortizacaoBase: 833.33,
  parcelas: [
    { numero: 1, amortizacao: 833.33, juros: 200.00, valor: 1033.33, saldoDevedor: 9166.67 },
    // ...
    { numero: 12, amortizacao: 833.37, juros: 16.67, valor: 850.04, saldoDevedor: 0 },
  ],
  totalJuros: 1300.00,
  totalPago: 11300.00,
}
```

### Passo a passo

1. Crie `src/lib/sac.js` com `export function calculaSac({ valor, taxaMes, prazoMeses })`.
2. Roteiro: `amortizacaoBase = arredonda2(valor / prazoMeses)`; `saldo = valor`; laço de `k = 1`
   até `prazoMeses`: `juros = arredonda2(saldo * taxaMes)`; `amortizacao = k < prazoMeses ?
   amortizacaoBase : saldo`; `valorParcela = arredonda2(amortizacao + juros)`;
   `saldo = arredonda2(saldo - amortizacao)`; push do objeto com os **mesmos nomes de campo** da T-02.
3. Totais com `reduce`, como na T-02.
4. Crie `src/lib/sac.test.js` copiando o modelo de `price.test.js` e usando os valores do
   **Anexo A.2**: `amortizacaoBase 833.33`; 1ª parcela `juros 200.00`, `valor 1033.33`,
   `saldoDevedor 9166.67`; 12ª parcela `amortizacao 833.37`, `valor 850.04`, `saldoDevedor 0`;
   `totalJuros 1300.00`; `totalPago 11300.00`.
5. `npm test` verde → PR.

### Critérios de aceite

- [ ] `npm test` passa (testes da T-02 e da T-03).
- [ ] Parcelas estritamente decrescentes (cada `valor` menor que o anterior, exceto possível ajuste de centavos na última).
- [ ] Saldo final exatamente `0`; soma das amortizações = `valor`.
- [ ] Nomes de campo idênticos aos da T-02.

### Armadilhas comuns

- Usar `amortizacaoBase` também na última parcela → sobra saldo de 0,04.
- Confundir os totais: no SAC os juros totais são **menores** que no Price para o mesmo prazo (1.300,00 contra 1.347,15) porque a dívida cai mais rápido no começo. Se der o contrário, tem bug.

---

## T-04 — Cronograma de amortização com datas reais

**Depende de:** T-02 ou T-03 (formato de `parcelas`). **Arquivos:** cria `src/lib/datas.js`,
`src/lib/datas.test.js`, `src/lib/cronograma.js`, `src/lib/cronograma.test.js`.

### O que é e por que existe

As funções Price e SAC trabalham com "mês 1, mês 2...". Mas o CET (T-06) é definido por lei em
**dias corridos** entre a liberação do dinheiro e cada pagamento, dividido por 365. Um mês pode
ter 28, 30 ou 31 dias e um vencimento pode cair no fim de semana — isso muda o CET. Esta tarefa
pega a lista de parcelas e acrescenta a cada uma a **data real de vencimento** e a quantidade de
**dias corridos** desde a liberação.

O arquivo legado `src/lib/calculaParcela.js` tenta fazer isso e tem **dois bugs clássicos** que
você vai aprender a evitar (ver "Conceitos"). Não altere o arquivo legado — a rota `/api/juros`
ainda depende dele; ele simplesmente não será usado pela nova API.

### Conceitos

**Regras de vencimento (decisão fechada):**
1. A parcela `k` vence **k meses** depois da liberação, **no mesmo dia do mês**.
   Liberação 30/10 → parcela 1 em 30/11, parcela 2 em 30/12...
2. Se o mês não tem esse dia, usa-se o **último dia do mês**. 30/10 + 4 meses = 30/02 não
   existe → **28/02/2027**.
3. Se o dia cair em **sábado ou domingo**, o vencimento passa para a **próxima segunda-feira**.
   30/01/2027 é sábado → **01/02/2027**. Feriados são ignorados.
4. O ajuste é feito **sempre a partir da data "de aniversário"**, nunca a partir do vencimento
   anterior já ajustado — senão as datas vão "escorregando" mês a mês.
5. `diasCorridos` = dias entre a data de liberação e o vencimento **já ajustado** (é a data em
   que o dinheiro efetivamente sai do bolso do cliente).

**Os dois bugs do código legado, e como evitá-los:**

- **Estouro de mês.** `new Date(2027, 1, 30)` (30 de fevereiro) não dá erro: o JavaScript
  "estoura" para 2 de março. Por isso é preciso calcular o último dia do mês e usar
  `Math.min(dia, ultimoDia)`. Truque: `new Date(Date.UTC(ano, mes + 1, 0))` é o dia **0** do
  mês seguinte = **último dia** do mês desejado.
- **Fuso horário.** `new Date(2026, 9, 30)` cria a data à meia-noite **no horário local**;
  `toISOString()` converte para UTC e, no Brasil (UTC−3), vira `2026-10-30T03:00:00Z`... ou,
  em outros casos, o **dia anterior**. Solução: trabalhe **só em UTC**: crie com `Date.UTC(...)`,
  leia com `getUTCDate()`, `getUTCDay()`, `getUTCMonth()`. Assim uma data é só "um dia", sem hora.

**Formato de data no projeto:** sempre **string `'AAAA-MM-DD'`** (ISO) na entrada e saída das
funções. Objetos `Date` só existem dentro de `datas.js`.

### Contrato

```js
// src/lib/datas.js
adicionaMeses('2026-10-30', 4)        // → '2027-02-28'  (30/02 não existe)
adicionaMeses('2026-01-31', 1)        // → '2026-02-28'
proximoDiaUtil('2027-01-30')          // → '2027-02-01'  (sábado → segunda)
proximoDiaUtil('2027-03-30')          // → '2027-03-30'  (terça, não muda)
diasEntre('2026-10-30', '2026-11-30') // → 31

// src/lib/cronograma.js
geraCronograma({ parcelas, dataLiberacao: '2026-10-30' })
// Devolve um NOVO array com as mesmas parcelas, cada uma com dois campos a mais:
// { numero, amortizacao, juros, valor, saldoDevedor, vencimento: '2026-11-30', diasCorridos: 31 }
```

### Passo a passo

**1. Crie `src/lib/datas.js`.** Como manipulação de datas é traiçoeira, o código está completo —
leia cada linha e entenda o porquê antes de copiar:

```js
const DIA_EM_MS = 24 * 60 * 60 * 1000;

// 'AAAA-MM-DD' → Date em UTC (meia-noite UTC daquele dia)
function paraData(iso) {
  const [ano, mes, dia] = iso.split('-').map(Number);
  return new Date(Date.UTC(ano, mes - 1, dia)); // mês em JS começa em 0 (janeiro = 0)
}

// Date → 'AAAA-MM-DD'
function paraIso(data) {
  return data.toISOString().slice(0, 10);
}

// Soma `meses` a uma data ISO, mantendo o dia; se o dia não existir no mês de destino,
// usa o último dia daquele mês.
export function adicionaMeses(iso, meses) {
  const base = paraData(iso);
  const ano = base.getUTCFullYear();
  const mes = base.getUTCMonth() + meses;       // pode passar de 11 — Date.UTC ajusta o ano
  const dia = base.getUTCDate();
  const ultimoDiaDoMes = new Date(Date.UTC(ano, mes + 1, 0)).getUTCDate(); // dia 0 do mês seguinte
  return paraIso(new Date(Date.UTC(ano, mes, Math.min(dia, ultimoDiaDoMes))));
}

// Se a data cair em sábado (6) ou domingo (0), avança até a próxima segunda.
export function proximoDiaUtil(iso) {
  let data = paraData(iso);
  while (data.getUTCDay() === 0 || data.getUTCDay() === 6) {
    data = new Date(data.getTime() + DIA_EM_MS);
  }
  return paraIso(data);
}

// Dias corridos entre duas datas ISO (fim − início).
export function diasEntre(isoInicio, isoFim) {
  return Math.round((paraData(isoFim) - paraData(isoInicio)) / DIA_EM_MS);
}

// Valida o formato 'AAAA-MM-DD' e se a data existe de verdade (rejeita 2026-02-30).
export function ehDataValida(texto) {
  if (typeof texto !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(texto)) return false;
  const data = paraData(texto);
  return !Number.isNaN(data.getTime()) && paraIso(data) === texto;
}
```

**2. Crie `src/lib/datas.test.js`** com os 5 exemplos do contrato acima como `assert.equal`
(um `test` por função). Inclua `ehDataValida('2026-02-30') === false` e
`ehDataValida('2026-02-28') === true`.

**3. Crie `src/lib/cronograma.js`:**

```js
import { adicionaMeses, proximoDiaUtil, diasEntre } from './datas.js';

export function geraCronograma({ parcelas, dataLiberacao }) {
  return parcelas.map((parcela) => {
    // 1. data "de aniversário": liberação + numero da parcela em meses
    // 2. ajusta para dia útil
    // 3. conta os dias corridos da liberação até a data ajustada
    // 4. devolve uma cópia da parcela com vencimento e diasCorridos:
    //    return { ...parcela, vencimento, diasCorridos };
  });
}
```

**4. Crie `src/lib/cronograma.test.js`:** gere as parcelas com `calculaPrice({ valor: 10000,
taxaMes: 0.02, prazoMeses: 12 })`, chame `geraCronograma` com `dataLiberacao: '2026-10-30'` e
confira contra o **Anexo A.3** — no mínimo as parcelas 1 (`2026-11-30`, 31 dias), 3 (`2027-02-01`,
94 dias — caiu no sábado), 4 (`2027-03-01`, 122 dias — 30/02 não existe **e** 28/02 é domingo)
e 12 (`2027-11-01`, 367 dias). Confira também que `parcelas[0].valor` continua `945.60` (os
campos originais não podem mudar) e que a entrada **não foi modificada** (o array original não
tem `vencimento`).

**5. `npm test` verde → PR.**

### Critérios de aceite

- [ ] Todas as funções de `datas.js` passam nos testes do contrato.
- [ ] `geraCronograma` devolve um **novo** array (não altera o de entrada), preservando todos os campos e acrescentando `vencimento` e `diasCorridos`.
- [ ] O cronograma de referência (Anexo A.3) bate em todas as 12 linhas.
- [ ] Nenhum uso de `new Date(ano, mes, dia)` sem `Date.UTC` ou de `getDate()/getMonth()/getDay()` (versões locais) em `datas.js`.

### Armadilhas comuns

- Rodar o teste e as datas virem um dia antes → você usou alguma função local (`getDate`, `new Date(a, m, d)`) em vez da versão UTC.
- Calcular a parcela 2 a partir do vencimento **ajustado** da parcela 1 → as datas escorregam. Sempre `adicionaMeses(dataLiberacao, parcela.numero)`.
- Esquecer o caso 28/02 domingo → 01/03 (parcela 4 do exemplo). Ele testa as duas regras ao mesmo tempo.

---

## T-05 — Encargos e tributos (IOF + tarifa de cadastro)

**Depende de:** T-04 (usa `amortizacao` e `diasCorridos` de cada parcela). **Arquivos:** cria
`src/dados/parametros.js`, `src/lib/encargos.js`, `src/lib/encargos.test.js`.

### O que é e por que existe

Além dos juros, um empréstimo tem custos que o cliente paga e que **entram no CET**:

- **IOF** (Imposto sobre Operações Financeiras) — tributo federal, Decreto 6.306/2007. Para
  pessoa física tem duas partes: uma **diária** sobre cada amortização e uma **adicional fixa**
  sobre o valor total.
- **Tarifa de cadastro** — Res. CMN 3.919/2010. Só pode ser cobrada **no início do
  relacionamento** com a instituição (STJ, Tema 620). Um simulador que sempre cobra a tarifa
  **superestima o CET** de cliente antigo — por isso ela depende de um dado de entrada.

Os percentuais **não ficam no código de cálculo**: ficam em `src/dados/parametros.js`, porque
mudam por decreto (as alíquotas de 2025 foram alteradas mais de uma vez).

### Conceitos

**IOF diário.** Cada parcela devolve um pedaço do principal (a `amortizacao`). Sobre esse pedaço
incide 0,0082% **por dia**, contando os `diasCorridos` até aquela parcela, **limitado a 365
dias** (parcelas com mais de 365 dias pagam como se fossem 365):

```
iofDiario = Σ  amortizacao_k × 0,000082 × min(diasCorridos_k, 365)
           k=1..n
```

No cenário de referência a parcela 12 tem 367 dias → conta como 365. Esse é o único caso em
que o limite atua em 12 meses; em 24 meses atuaria em metade das parcelas.

**IOF adicional.** `0,38% × valor` — uma vez só, sobre o valor total do crédito.

**Tarifa de cadastro.** Valor fixo (R$ 50,00 provisório) cobrado **apenas** se
`primeiroRelacionamento === true`. Caso contrário, `0`.

**Onde esses valores entram na operação?** Decisão fechada: são **descontados do valor
liberado**. O cliente pede 10.000, os encargos somam 256,09, ele **recebe** 9.743,91 e paga as
parcelas calculadas sobre 10.000. Isso é exatamente o "FC0 = valor deduzido das despesas pagas
antecipadamente" da Res. 4.881 — e é o que a T-06 vai usar.

### Contrato

```js
// src/dados/parametros.js
export const PARAMETROS = {
  IOF_ALIQUOTA_DIARIA: 0.000082,   // 0,0082% ao dia (PF)
  IOF_ALIQUOTA_ADICIONAL: 0.0038,  // 0,38% sobre o valor
  IOF_DIAS_MAXIMO: 365,
  TARIFA_CADASTRO: 50.00,          // R$ — provisório, definido pela equipe
};

// src/lib/encargos.js
calculaEncargos({ valor, cronograma, primeiroRelacionamento })
// valor: principal (ex.: 10000)
// cronograma: saída da T-04 (precisa de amortizacao e diasCorridos em cada parcela)
// primeiroRelacionamento: boolean

// Retorna:
{
  iof: { diario: 168.09, adicional: 38.00, total: 206.09 },
  tarifaCadastro: 50.00,
  total: 256.09,
}
```

### Passo a passo

1. Crie `src/dados/parametros.js` com o objeto acima (adicione um comentário com a fonte:
   Decreto 6.306/2007 e Res. CMN 3.919/2010).
2. Crie `src/lib/encargos.js` importando `PARAMETROS` e `arredonda2`. Roteiro:
   - `somaDiario = 0`; para cada parcela do cronograma:
     `somaDiario += parcela.amortizacao * IOF_ALIQUOTA_DIARIA * Math.min(parcela.diasCorridos, IOF_DIAS_MAXIMO)`.
     **Não** arredonde dentro do laço — arredonde só o total: `iofDiario = arredonda2(somaDiario)`.
   - `iofAdicional = arredonda2(valor * IOF_ALIQUOTA_ADICIONAL)`
   - `iofTotal = arredonda2(iofDiario + iofAdicional)`
   - `tarifaCadastro = primeiroRelacionamento ? TARIFA_CADASTRO : 0`
   - `total = arredonda2(iofTotal + tarifaCadastro)`
   - devolva o objeto no formato do contrato.
3. Crie `src/lib/encargos.test.js`. Monte o cronograma de referência (Price 10.000 / 2% / 12 /
   liberação `2026-10-30`, como na T-04) e teste:
   - `primeiroRelacionamento: true` → `iof.diario 168.09`, `iof.adicional 38.00`,
     `iof.total 206.09`, `tarifaCadastro 50.00`, `total 256.09`.
   - `primeiroRelacionamento: false` → `tarifaCadastro 0`, `total 206.09`.
   - Mesmo cenário com o cronograma **SAC** → `iof.diario 162.22`, `total 250.22` (com tarifa).
     O SAC tem IOF menor porque amortiza mais cedo — se o seu der maior, tem bug.
4. `npm test` verde → PR.

### Critérios de aceite

- [ ] Os três cenários de teste passam com os valores acima.
- [ ] Nenhuma alíquota escrita diretamente em `encargos.js` — todas vêm de `PARAMETROS`.
- [ ] Tarifa de cadastro é `0` quando `primeiroRelacionamento` é `false` **ou ausente**.
- [ ] O limite de 365 dias está aplicado (`Math.min`).

### Armadilhas comuns

- Aplicar o IOF diário sobre o **valor da parcela** em vez da **amortização** → IOF inflado.
- Arredondar cada termo do somatório antes de somar → diverge centavos do valor esperado.
- Usar `diasCorridos` sem o `Math.min(…, 365)` — no cenário de referência só a parcela 12 revela o erro (168,09 vira 168,24).

---

## T-06 — CET (Custo Efetivo Total) e demonstrativo

**Depende de:** T-04 e T-05. **Arquivos:** cria `src/lib/cet.js`, `src/lib/cet.test.js`,
`src/lib/demonstrativo.js`, `src/lib/demonstrativo.test.js`.

### O que é e por que existe

O **CET** é a taxa que o cliente **realmente paga** quando se consideram **todos** os custos —
juros, IOF, tarifas — e as **datas reais** dos pagamentos. É obrigatório por lei informá-lo
(Resolução CMN 4.881/2020) e, junto com ele, um **demonstrativo** com o valor em reais de cada
componente e seu percentual sobre o total devido (art. 7º).

> Atenção: muitos tutoriais na internet citam a Resolução 3.517/2007. Ela foi **revogada**.
> A norma vigente é a **4.881/2020**. Não use fórmulas "mensais idealizadas" de blog.

### Conceitos

**A equação do CET (art. 4º da Res. 4.881):**

```
          N          FC_j
FC_0  =   Σ   ────────────────────────
         j=1   (1 + CET)^((d_j − d_0) / 365)
```

- `FC_0` = **valor que o cliente recebeu** = `valor − encargos.total` (o "valor liberado").
  No cenário de referência: 10.000 − 256,09 = **9.743,91**.
- `FC_j` = **valor de cada parcela** (`parcela.valor`).
- `d_j − d_0` = **dias corridos** da liberação ao pagamento (`parcela.diasCorridos`) — exatamente
  o que a T-04 calculou.
- `CET` = taxa **anual** decimal que faz a igualdade valer.

Em palavras: "qual taxa anual faz o valor presente de todas as parcelas ser igual ao que o
cliente recebeu?". É a mesma ideia de TIR (taxa interna de retorno).

**Por que não dá para isolar o CET?** Ele aparece no expoente de cada termo da soma. Não existe
fórmula fechada — é preciso **procurar** o valor numericamente.

**Bisseção — o método que vamos usar.** Defina a função

```
f(cet) = Σ FC_j / (1 + cet)^(dias_j/365)  −  FC_0
```

Queremos o `cet` em que `f(cet) = 0`. Sabemos que `f` **diminui** quando `cet` aumenta (quanto
maior a taxa, menor o valor presente das parcelas). Então:

1. Comece com um intervalo `[lo, hi] = [0, 10]` (0% a 1000% ao ano — cobre qualquer crédito
   real). Se `f(lo) > 0` e `f(hi) < 0`, existe uma raiz no meio. Se não, o fluxo não faz
   sentido → erro `CET_NAO_CONVERGE`.
2. Calcule o ponto médio `meio = (lo + hi) / 2`.
3. Se `f(meio) > 0`, a raiz está à direita → `lo = meio`. Senão, está à esquerda → `hi = meio`.
4. Repita até o intervalo ficar minúsculo (`hi − lo < 1e-10`) ou 200 iterações. O CET é o ponto médio final.

É o jogo de "adivinhe o número entre 0 e 100 — é maior ou menor?": a cada palpite o intervalo
cai pela metade; em 40 palpites já temos precisão de 1e-11.

**Do anual ao mensal e a apresentação:** `cetMensal = (1 + cetAnual)^(1/12) − 1`. Para
apresentar: `% = arredonda2(cet × 100)`, duas casas (a norma pede arredondamento ABNT NBR 5891;
`arredonda2` difere dele só em casos de empate exato em 5, aceito como simplificação).

**Verificação de sanidade que você deve fazer:** se calcular o CET **sem** encargos (`FC_0 =
10.000`) sobre o cronograma Price a 2% a.m., o CET mensal tem de dar **2,00%** — o CET de um
fluxo sem custos extras é a própria taxa de juros. Se não der, a função está errada.

**Demonstrativo (art. 7º).** Para cada componente do custo: valor em R$ e percentual sobre o
**total devido**; mais o somatório das parcelas.

```
totalDevido        = somatorioParcelas + encargos.total     (tudo que sai do bolso do cliente)
componentes        = Principal (valor), Juros (totalJuros), IOF (encargos.iof.total),
                     Tarifa de cadastro (encargos.tarifaCadastro)
percentual de cada = arredonda2(componente / totalDevido × 100)
```

Os quatro componentes somados dão exatamente o `totalDevido` (principal + juros = parcelas).

### Contrato

```js
// src/lib/cet.js
calculaCet({ valorLiberado, cronograma })
// valorLiberado: FC_0 (ex.: 9743.91)
// cronograma: saída da T-04 (usa .valor e .diasCorridos de cada parcela)
// Retorna taxas DECIMAIS (sem arredondar — quem apresenta arredonda):
{ cetAnual: 0.33254..., cetMensal: 0.02423... }
// Lança ErroDeNegocio(422, 'CET_NAO_CONVERGE', ...) se não houver raiz em [0, 10].

// src/lib/demonstrativo.js
montaDemonstrativo({ valor, totalJuros, encargos, cronograma })
// Retorna:
{
  componentes: [
    { descricao: 'Principal (valor do crédito)', valor: 10000.00, percentualSobreTotalDevido: 86.18 },
    { descricao: 'Juros',                        valor: 1347.15,  percentualSobreTotalDevido: 11.61 },
    { descricao: 'IOF',                          valor: 206.09,   percentualSobreTotalDevido: 1.78 },
    { descricao: 'Tarifa de cadastro',           valor: 50.00,    percentualSobreTotalDevido: 0.43 },
  ],
  somatorioParcelas: 11347.15,
  totalDevido: 11603.24,
}
```

### Passo a passo

**1. Crie `src/lib/cet.js`.** O esqueleto da bisseção está completo porque é o ponto mais
delicado; a função `f` é sua:

```js
import { ErroDeNegocio } from './erros.js';

export function calculaCet({ valorLiberado, cronograma }) {
  // f(cet): valor presente das parcelas menos o valor liberado.
  // Percorra o cronograma somando  parcela.valor / (1 + cet) ** (parcela.diasCorridos / 365)
  // e no final subtraia valorLiberado.
  const f = (cet) => {
    // TODO
  };

  let lo = 0;   // 0% ao ano
  let hi = 10;  // 1000% ao ano

  if (!(f(lo) > 0 && f(hi) < 0)) {
    throw new ErroDeNegocio(422, 'CET_NAO_CONVERGE',
      'Não foi possível calcular o CET para este fluxo de pagamentos');
  }

  for (let iteracao = 0; iteracao < 200 && hi - lo > 1e-10; iteracao++) {
    const meio = (lo + hi) / 2;
    if (f(meio) > 0) lo = meio;   // raiz está à direita
    else hi = meio;               // raiz está à esquerda
  }

  const cetAnual = (lo + hi) / 2;
  const cetMensal = (1 + cetAnual) ** (1 / 12) - 1;
  return { cetAnual, cetMensal };
}
```

**2. Crie `src/lib/cet.test.js`.** Monte o cenário de referência (Price 10.000 / 2% / 12 /
`2026-10-30` → cronograma → encargos com tarifa) e teste:
- `valorLiberado = arredonda2(10000 - encargos.total)` deve ser `9743.91`;
- `arredonda2(cetAnual * 100)` → `33.25`; `arredonda2(cetMensal * 100)` → `2.42`;
- **sanidade:** `calculaCet({ valorLiberado: 10000, cronograma })` → `arredonda2(cetMensal * 100)` = `2.00`;
- **erro:** um cronograma em que a soma das parcelas é **menor** que o valor liberado (ex.:
  `valorLiberado: 20000` com o mesmo cronograma) deve lançar erro com `codigo === 'CET_NAO_CONVERGE'`
  (use `assert.throws(() => ..., (e) => e.codigo === 'CET_NAO_CONVERGE')`).

**3. Crie `src/lib/demonstrativo.js`.** Roteiro:
- `somatorioParcelas = arredonda2(soma de cronograma[].valor)`
- `totalDevido = arredonda2(somatorioParcelas + encargos.total)`
- uma pequena função interna `componente(descricao, v)` que devolve
  `{ descricao, valor: v, percentualSobreTotalDevido: arredonda2((v / totalDevido) * 100) }`
- monte o array com os 4 componentes **nesta ordem** e devolva o objeto do contrato.

**4. Crie `src/lib/demonstrativo.test.js`** com os valores do contrato acima (cenário de
referência). Confira também que a soma dos 4 `valor` é igual a `totalDevido` (com `arredonda2`).

**5. `npm test` verde → PR.**

### Critérios de aceite

- [ ] CET do cenário de referência: **33,25% a.a. / 2,42% a.m.**
- [ ] Sanidade: sem encargos, o CET mensal é igual à taxa (2,00%).
- [ ] Fluxo impossível lança `ErroDeNegocio` 422 `CET_NAO_CONVERGE` (não trava, não devolve `NaN`).
- [ ] Demonstrativo com os 4 componentes na ordem definida, percentuais sobre `totalDevido`, e `somatorioParcelas`.
- [ ] `cet.js` devolve decimais **não arredondados**; o arredondamento fica para quem apresenta (T-07).

### Armadilhas comuns

- Usar `diasCorridos / 360` ou `/ 30` — a norma diz **365** e dias corridos.
- Usar `parcela.amortizacao` em vez de `parcela.valor` como `FC_j`. O CET considera o pagamento **inteiro**.
- Inverter o `if` da bisseção (`f(meio) > 0 → hi = meio`) — o laço converge para 0 ou 10 e o teste de sanidade falha.
- Calcular o CET sobre `valor` (10.000) em vez de sobre o `valorLiberado` (9.743,91) — o CET sai igual à taxa de juros e os encargos "desaparecem".

---

## T-07 — `POST /api/operacoes`: simular e gravar a operação

**Depende de:** T-01 a T-06 (Partes B–D e F).
**Arquivos:** cria `src/dados/faixasRisco.js`, `src/servicos/taxa.js`, `src/servicos/validaEntrada.js`,
`src/servicos/simulacao.js`, `src/routes/operacoes.js`; altera `src/routes/index.js`.

> **O que a equipe de banco já entregou (não refaça):** a **Parte A** (MySQL, `db/schema.sql`,
> `db/seed.sql`, `.env.example`, `mysql2`, `src/db.js`, `/api/health` com banco) e a **Parte E**
> (`src/repositorios/operacoes.js` completo, inclusive a função `listar` da T-08). Neste guia as
> Partes A e E ficaram só como **leitura**: o que você precisa saber para usar o que já existe.

É a tarefa maior. Está dividida em partes (A a F) que podem ser feitas por pessoas diferentes,
**na ordem**, cada parte com seu commit.

### O que é e por que existe

É o coração da API: recebe `identificador`, `valor`, `modalidade`, `score`, `prazoMeses` (e,
opcionalmente, `dataLiberacao` e `primeiroRelacionamento`), valida tudo, descobre a taxa a
partir da modalidade e do score, roda **Price e SAC** com cronograma, encargos, CET e
demonstrativo, **grava** a operação no MySQL e devolve o resultado completo.

> O pedido do produto fala em "valor, modalidade, score e identificação". O **prazo** também é
> obrigatório — sem ele não existe parcela. A **data de liberação** é opcional (padrão: hoje),
> mas nos testes envie sempre, para o resultado ser reproduzível.

### Contrato do endpoint

**Requisição:** `POST /api/operacoes` com corpo JSON:

```json
{
  "identificador": "OP-2026-0001",
  "valor": 10000,
  "modalidade": "CONSIGNADO_INSS",
  "score": 650,
  "prazoMeses": 12,
  "dataLiberacao": "2026-10-30",
  "primeiroRelacionamento": true
}
```

| Campo | Tipo | Regra | Erro se violar |
|---|---|---|---|
| `identificador` | string | obrigatório, 1 a 60 caracteres, único | 400 / 409 se já existir |
| `valor` | number | obrigatório, > 0 e ≤ 10.000.000 | 400 |
| `modalidade` | string | obrigatório, deve existir no catálogo (T-01) | 400 |
| `score` | inteiro | obrigatório, 0 a 1000 | 400 |
| `prazoMeses` | inteiro | obrigatório, entre `prazoMinMeses` e `prazoMaxMeses` da modalidade | 400 |
| `dataLiberacao` | string | opcional, `AAAA-MM-DD` válida; padrão = hoje | 400 |
| `primeiroRelacionamento` | boolean | opcional; padrão `false` | 400 se vier e não for boolean |

**Resposta `201 Created`** (valores do cenário ponta a ponta — **Anexo A.5**):

```json
{
  "id": 1,
  "identificador": "OP-2026-0001",
  "criadoEm": "2026-09-21 14:03:22",
  "entrada": {
    "valor": 10000, "modalidade": "CONSIGNADO_INSS", "score": 650, "prazoMeses": 12,
    "dataLiberacao": "2026-10-30", "primeiroRelacionamento": true
  },
  "taxa": {
    "faixaRisco": "B", "taxaBaseMes": 1.60, "spreadMes": 0.50,
    "tetoTaxaMes": 1.85, "taxaFinalMes": 1.85, "tetoAplicado": true
  },
  "simulacoes": {
    "PRICE": {
      "sistema": "PRICE",
      "parcelaFixa": 936.91,
      "totalJuros": 1242.88,
      "totalPago": 11242.88,
      "encargos": { "iof": { "diario": 167.65, "adicional": 38.00, "total": 205.65 }, "tarifaCadastro": 50.00, "total": 255.65 },
      "valorLiberado": 9744.35,
      "cet": { "anualPercentual": 30.89, "mensalPercentual": 2.27 },
      "demonstrativo": { "componentes": [ "..." ], "somatorioParcelas": 11242.88, "totalDevido": 11498.53 },
      "cronograma": [ { "numero": 1, "amortizacao": 751.91, "juros": 185.00, "valor": 936.91, "saldoDevedor": 9248.09, "vencimento": "2026-11-30", "diasCorridos": 31 }, "..." ]
    },
    "SAC": { "sistema": "SAC", "amortizacaoBase": 833.33, "totalJuros": 1202.50, "totalPago": 11202.50, "valorLiberado": 9749.78, "cet": { "anualPercentual": 30.96, "mensalPercentual": 2.27 }, "...": "..." }
  }
}
```

**Erros:** `400 DADOS_INVALIDOS` (com `detalhes` listando **todos** os problemas, não só o
primeiro), `409 IDENTIFICADOR_DUPLICADO`, `422 SCORE_INSUFICIENTE` (faixa E), `422 CET_NAO_CONVERGE`,
`500 ERRO_INTERNO`.

### Conceitos

**Score → faixa → spread → taxa (regra RN02 do inventário).** O score (0–1000) classifica o
cliente em uma faixa de risco; cada faixa **soma** um spread à taxa base da modalidade; o
resultado é **limitado ao teto**:

| Faixa | Score | Spread (p.p. ao mês) |
|---|---|---|
| A | 800–1000 | +0,00 |
| B | 600–799 | +0,50 |
| C | 400–599 | +1,00 |
| D | 200–399 | +2,00 |
| E | 0–199 | **recusa** (422 `SCORE_INSUFICIENTE`) |

```
taxaFinalMes = min(taxaBaseMes + spreadMes, tetoTaxaMes)
```

Exemplo do cenário: consignado INSS (base 1,60; teto 1,85), score 650 → faixa B → 1,60 + 0,50 =
2,10 → **limitado a 1,85**. `tetoAplicado: true` avisa que o teto atuou. Já `CREDITO_PESSOAL`
com score 720 → 4,50 + 0,50 = **5,00** (teto 12,00 não atua).

**Conversão de unidade.** O catálogo está em **%** (`1.85`). As funções de `src/lib` querem
**decimal**. A conversão `taxaFinalMes / 100` acontece **uma única vez**, no serviço de simulação.

**Banco de dados.** O banco `calculo_juros` tem **3 tabelas** (`db/schema.sql`, mantido pela
equipe de banco):

| Tabela | O que guarda | Quem usa |
|---|---|---|
| `modalidades` | catálogo das modalidades (chave primária = `codigo`) | carga inicial do seed; a API ainda lê o catálogo de `src/dados/modalidades.js` |
| `faixas_juros` | taxa por modalidade × faixa de score | carga inicial do seed; uso futuro da API |
| `operacoes` | cada operação simulada | **T-07 grava, T-08 lê** |

Na tabela `operacoes`, as colunas "planas" (`valor`, `score`, `cet_price_ano`…) servem para a
**listagem** da T-08 ser leve; a coluna `resultado` (tipo `JSON`) guarda a resposta completa para
o `GET /:id`. Não normalizamos parcelas em outra tabela — fora do escopo.

Dois detalhes do schema real que afetam a API:

- A coluna da modalidade chama-se **`modalidade_codigo`** (não `modalidade`). No JSON da API o
  campo continua sendo `modalidade`; a tradução é feita no repositório.
- `modalidade_codigo` é **chave estrangeira** para `modalidades.codigo`. Ou seja: **só é
  possível gravar uma operação se o código da modalidade existir na tabela `modalidades`**. Por
  isso o `npm run seed` é obrigatório antes de testar o `POST`, e os códigos do seed precisam ser
  **os mesmos** do catálogo da T-01 (`CONSIGNADO_INSS`, `CREDITO_PESSOAL`…). Se o INSERT falhar
  com `ER_NO_REFERENCED_ROW_2`, o seed da sua máquina está desatualizado ou com códigos
  diferentes — avise a equipe de banco; não "resolva" removendo a chave estrangeira.

**Variáveis de ambiente.** Senha de banco **nunca** vai para o código nem para o git. Fica no
arquivo `.env` (ignorado pelo git), lido pelo Node com a flag `--env-file=.env`. O `.env.example`
mostra o formato sem valores reais.

### Parte A — Banco de dados (já entregue pela equipe de banco; rode na sua máquina)

Nada aqui é para programar. A equipe de banco já criou `db/schema.sql`, `db/seed.sql`,
`src/db.js`, `.env.example`, instalou o `mysql2` e fez o `/api/health` checar o banco. O que
**você** precisa fazer é deixar o banco funcionando no seu computador:

**A1. Instale o MySQL 8** (se ainda não tem) pelo instalador
<https://dev.mysql.com/downloads/installer/> → "Developer Default" (instala o servidor e o
**MySQL Workbench**). Anote a senha do `root`. Detalhes em `docs/backlog-db.md`, D-00.

**A2. Crie o `.env`.** Copie `.env.example` para `.env` e coloque a senha real do seu MySQL:

```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=sua-senha-aqui
DB_NAME=calculo_juros
PORT=3000
```

O `.env` já está no `.gitignore`. Rode `git status` e confirme que ele **não** aparece.

**A3. Instale as dependências e crie o banco com dados:**

```
npm install
npm run schema     # cria o banco calculo_juros e as 3 tabelas (pode rodar várias vezes)
npm run seed       # carrega as 6 modalidades e as 30 faixas de juros (idem)
```

O `schema` imprime `tabelas: faixas_juros, modalidades, operacoes` e o `seed` imprime
`modalidades: 6` e `faixas_juros: 30`. **Sem o seed, o `POST /api/operacoes` não grava nada**
(ver "Banco de dados" em Conceitos: chave estrangeira para `modalidades`).

**A4. Confira:** `npm run dev` → `GET /api/health` → `{ "status": "ok", "banco": "ok" }`. Se vier
`503`, o MySQL está parado ou o `.env` está errado.

**A5. Conheça a tabela que a T-07 usa.** É esta (trecho do `db/schema.sql` real — **não** edite
o arquivo; se precisar de uma coluna nova, peça à equipe de banco):

```sql
CREATE TABLE IF NOT EXISTS operacoes (
  id                      INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  identificador           VARCHAR(60)       NOT NULL,
  modalidade_codigo       VARCHAR(40)       NOT NULL,   -- FK -> modalidades.codigo
  valor                   DECIMAL(15,2)     NOT NULL,
  score                   SMALLINT UNSIGNED NOT NULL,
  prazo_meses             SMALLINT UNSIGNED NOT NULL,
  data_liberacao          DATE              NOT NULL,
  primeiro_relacionamento BOOLEAN           NOT NULL DEFAULT FALSE,
  faixa_risco             CHAR(1)           NOT NULL,
  taxa_final_mes          DECIMAL(8,4)      NOT NULL,
  cet_price_ano           DECIMAL(8,2)      NOT NULL,
  cet_sac_ano             DECIMAL(8,2)      NOT NULL,
  resultado               JSON              NOT NULL,   -- resposta completa (entrada, taxa, simulacoes)
  criado_em               DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_operacoes_identificador (identificador),
  CONSTRAINT fk_operacoes_modalidade FOREIGN KEY (modalidade_codigo) REFERENCES modalidades (codigo),
  CONSTRAINT ck_operacoes_valor CHECK (valor > 0),
  CONSTRAINT ck_operacoes_score CHECK (score <= 1000)
);
```

Convenção: no banco, nomes em `snake_case` (`prazo_meses`, `modalidade_codigo`); no JavaScript,
`camelCase` (`prazoMeses`, `modalidade`). O repositório (Parte E) faz a tradução.

**A6. Como o `src/db.js` já está configurado** (só para você entender o que recebe):
`decimalNumbers: true` faz colunas `DECIMAL` voltarem como **número** (sem isso, `"10000.00"`
string); `dateStrings: true` faz `DATE` voltar como `'AAAA-MM-DD'` (sem isso, objeto `Date` com
fuso). Nunca abra conexão por requisição — use sempre o `pool` exportado de lá.

### Parte B — Score → faixa → taxa

**B1. Crie `src/dados/faixasRisco.js`:**

```js
// Faixas de risco por score (0–1000). Spread em pontos percentuais ao mês, somado à taxa base.
export const FAIXAS_RISCO = [
  { faixa: 'A', scoreMin: 800, scoreMax: 1000, spreadMes: 0.00, descricao: 'Risco muito baixo' },
  { faixa: 'B', scoreMin: 600, scoreMax: 799,  spreadMes: 0.50, descricao: 'Risco baixo' },
  { faixa: 'C', scoreMin: 400, scoreMax: 599,  spreadMes: 1.00, descricao: 'Risco médio' },
  { faixa: 'D', scoreMin: 200, scoreMax: 399,  spreadMes: 2.00, descricao: 'Risco alto' },
  { faixa: 'E', scoreMin: 0,   scoreMax: 199,  spreadMes: null, descricao: 'Recusado: score abaixo do mínimo' },
];

export function classificaScore(score) {
  return FAIXAS_RISCO.find((f) => score >= f.scoreMin && score <= f.scoreMax);
}
```

**B2. Crie `src/servicos/taxa.js`** com `export function calculaTaxa(modalidade, score)`:
1. `faixa = classificaScore(score)`.
2. Se `faixa.spreadMes === null` → `throw new ErroDeNegocio(422, 'SCORE_INSUFICIENTE',
   'Score abaixo do mínimo para contratação')`.
3. `semTeto = arredonda2(modalidade.taxaBaseMes + faixa.spreadMes)`.
4. `taxaFinalMes = Math.min(semTeto, modalidade.tetoTaxaMes)`.
5. Devolva `{ faixaRisco: faixa.faixa, taxaBaseMes, spreadMes, tetoTaxaMes, taxaFinalMes, tetoAplicado: semTeto > modalidade.tetoTaxaMes }`.

**B3. Teste** em `src/servicos/taxa.test.js`: INSS + 650 → `taxaFinalMes 1.85`, `tetoAplicado true`;
`CREDITO_PESSOAL` + 720 → `5.00`, `tetoAplicado false`; qualquer modalidade + 150 → lança
`SCORE_INSUFICIENTE`. **Commit.**

### Parte C — Validação da entrada

**C1. Crie `src/servicos/validaEntrada.js`** com `export function validaEntrada(body)`.
A ideia: uma lista `erros = []`; cada regra da tabela do contrato faz um `if` e, se violada,
dá `erros.push('mensagem clara')`. **Não pare no primeiro erro** — o cliente da API quer ver
todos de uma vez. No final:

- se `erros.length > 0` → `throw new ErroDeNegocio(400, 'DADOS_INVALIDOS', 'Há campos inválidos na requisição', erros)`;
- senão, devolva a **entrada normalizada**: `{ identificador, valor, modalidade (o OBJETO do
  catálogo), score, prazoMeses, dataLiberacao (preenchida com hoje se ausente), primeiroRelacionamento (false se ausente) }`.

Dicas de implementação:
- `body ?? {}` no início (corpo vazio não pode derrubar o servidor).
- Inteiro: `Number.isInteger(x)`. Número finito: `typeof x === 'number' && Number.isFinite(x)`.
- Data válida: `ehDataValida` da T-04. Hoje em ISO: `new Date().toISOString().slice(0, 10)`.
- `prazoMeses` tem duas checagens: a básica (obrigatório, inteiro ≥ 1) é feita **sempre**; a de
  faixa (`prazoMinMeses`–`prazoMaxMeses`) só é possível se a modalidade foi encontrada.
- Exemplos de mensagem: `"valor deve ser um número maior que zero"`, `"prazoMeses deve estar entre 6 e 84 para CONSIGNADO_INSS"`.

**C2. Teste** em `src/servicos/validaEntrada.test.js`: corpo válido devolve normalizado com
`primeiroRelacionamento false`; corpo `{}` lança 400 com **5** mensagens em `detalhes`
(identificador, valor, modalidade, score, prazoMeses); prazo 3 em INSS lança 400 citando 6 e 84.
**Commit.**

### Parte D — Serviço de simulação (junta as peças)

**D1. Crie `src/servicos/simulacao.js`** com `export function simulaOperacao(entrada)`
(`entrada` = saída da `validaEntrada`). Roteiro:

```js
import { calculaPrice } from '../lib/price.js';
import { calculaSac } from '../lib/sac.js';
import { geraCronograma } from '../lib/cronograma.js';
import { calculaEncargos } from '../lib/encargos.js';
import { calculaCet } from '../lib/cet.js';
import { montaDemonstrativo } from '../lib/demonstrativo.js';
import { arredonda2 } from '../lib/util.js';
import { calculaTaxa } from './taxa.js';

export function simulaOperacao(entrada) {
  const { valor, modalidade, score, prazoMeses, dataLiberacao, primeiroRelacionamento } = entrada;

  // 1. taxa = calculaTaxa(modalidade, score)          ← pode lançar SCORE_INSUFICIENTE
  // 2. taxaMes = taxa.taxaFinalMes / 100              ← ÚNICO lugar onde % vira decimal
  // 3. Para cada função em [calculaPrice, calculaSac]:
  //    a. resultado = funcao({ valor, taxaMes, prazoMeses })
  //    b. cronograma = geraCronograma({ parcelas: resultado.parcelas, dataLiberacao })
  //    c. encargos = calculaEncargos({ valor, cronograma, primeiroRelacionamento })
  //    d. valorLiberado = arredonda2(valor - encargos.total)
  //    e. cet = calculaCet({ valorLiberado, cronograma })    ← pode lançar CET_NAO_CONVERGE
  //    f. demonstrativo = montaDemonstrativo({ valor, totalJuros: resultado.totalJuros, encargos, cronograma })
  //    g. monte o objeto do sistema:
  //       { sistema, parcelaFixa ou amortizacaoBase, totalJuros, totalPago, encargos, valorLiberado,
  //         cet: { anualPercentual: arredonda2(cet.cetAnual * 100), mensalPercentual: arredonda2(cet.cetMensal * 100) },
  //         demonstrativo, cronograma }
  //       (dica: comece com { ...resultado } e remova `parcelas`, que foi substituído por `cronograma`)
  // 4. return {
  //      entrada: { valor, modalidade: modalidade.codigo, score, prazoMeses, dataLiberacao, primeiroRelacionamento },
  //      taxa,
  //      simulacoes: { PRICE: ..., SAC: ... },
  //    }
}
```

**D2. Teste** em `src/servicos/simulacao.test.js` com o cenário ponta a ponta (**Anexo A.5**):
`taxa.taxaFinalMes 1.85`; `simulacoes.PRICE.parcelaFixa 936.91`; `PRICE.encargos.total 255.65`;
`PRICE.valorLiberado 9744.35`; `PRICE.cet.anualPercentual 30.89`; `SAC.totalJuros 1202.50`;
`SAC.cet.anualPercentual 30.96`; `PRICE.cronograma.length 12`; `PRICE.cronograma[0].vencimento '2026-11-30'`.
**Commit.**

### Parte E — Repositório (SQL) — já entregue pela equipe de banco

O arquivo `src/repositorios/operacoes.js` **já existe e está completo** (D-05 do
`docs/backlog-db.md`). Não reescreva. O que você precisa saber para usar na Parte F:

| Função | Recebe | Devolve |
|---|---|---|
| `existeIdentificador(identificador)` | string | `true`/`false` |
| `salvar({ identificador, entrada, taxa, simulacoes })` | a saída de `simulaOperacao` + o identificador | o `id` gerado |
| `buscarPorId(id)` | número | a operação completa (`id`, `identificador`, `criadoEm`, `entrada`, `taxa`, `simulacoes`) ou `undefined` |
| `listar({ pagina, tamanho })` | números | `{ itens, total }` — usada na T-08 |

Como o `salvar` grava (leia para entender o mapeamento; repare em `modalidade_codigo`):

```js
export async function salvar({ identificador, entrada, taxa, simulacoes }) {
  const [resultado] = await pool.query(
    `INSERT INTO operacoes
       (identificador, modalidade_codigo, valor, score, prazo_meses, data_liberacao,
        primeiro_relacionamento, faixa_risco, taxa_final_mes, cet_price_ano, cet_sac_ano, resultado)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      identificador, entrada.modalidade, entrada.valor, entrada.score, entrada.prazoMeses,
      entrada.dataLiberacao, entrada.primeiroRelacionamento ? 1 : 0,
      taxa.faixaRisco, taxa.taxaFinalMes,
      simulacoes.PRICE.cet.anualPercentual, simulacoes.SAC.cet.anualPercentual,
      JSON.stringify({ entrada, taxa, simulacoes }),
    ],
  );
  return resultado.insertId;
}
```

Consequências para a Parte D: `entrada.modalidade` tem de ser a **string do código**
(`'CONSIGNADO_INSS'`), não o objeto do catálogo; `taxa.faixaRisco` e `taxa.taxaFinalMes` têm de
existir; `simulacoes.PRICE.cet.anualPercentual` e `simulacoes.SAC.cet.anualPercentual` também.
Se o `simulaOperacao` devolver outro formato, o `salvar` quebra.

Toda função usa `pool.query(sql, [parametros])` com `?` — **nunca** monte SQL concatenando
strings com dados do usuário (evita SQL injection). Se precisar de uma consulta nova, peça à
equipe de banco ou adicione no mesmo estilo, com `?`.

### Parte F — A rota

**F1. Crie `src/routes/operacoes.js`:**

```js
import { Router } from 'express';
import { validaEntrada } from '../servicos/validaEntrada.js';
import { simulaOperacao } from '../servicos/simulacao.js';
import * as repositorio from '../repositorios/operacoes.js';
import { ErroDeNegocio } from '../lib/erros.js';

const router = Router();

// POST /api/operacoes
router.post('/', async (req, res) => {
  // 1. const entrada = validaEntrada(req.body);                 ← 400 se inválido
  // 2. if (await repositorio.existeIdentificador(entrada.identificador))
  //      throw new ErroDeNegocio(409, 'IDENTIFICADOR_DUPLICADO', `Já existe operação com identificador "${...}"`);
  // 3. const simulacao = simulaOperacao(entrada);               ← 422 se score/CET
  // 4. const id = await repositorio.salvar({ identificador: entrada.identificador, ...simulacao });
  // 5. const operacao = await repositorio.buscarPorId(id);
  // 6. res.status(201).json(operacao);
});

export default router;
```

**F2. Registre** em `src/routes/index.js`: `router.use('/operacoes', operacoesRoutes);`.

**F3. Teste no Postman** (Body → raw → JSON):

| Cenário | Corpo | Esperado |
|---|---|---|
| Feliz | o JSON do contrato (`OP-2026-0001`) | `201`; `taxa.taxaFinalMes 1.85`; `simulacoes.PRICE.parcelaFixa 936.91`; `PRICE.cet.anualPercentual 30.89`; `SAC.cet.anualPercentual 30.96` |
| Repetido | mesmo corpo de novo | `409 IDENTIFICADOR_DUPLICADO` |
| Inválido | `{}` | `400 DADOS_INVALIDOS` com 5 itens em `detalhes` |
| Prazo fora | INSS com `prazoMeses: 3` | `400` citando "entre 6 e 84" |
| Score baixo | `score: 150`, identificador novo | `422 SCORE_INSUFICIENTE` (e **nada** gravado no banco) |
| Sem data | sem `dataLiberacao`, identificador novo | `201` com `entrada.dataLiberacao` = hoje |

Confira no Workbench: `SELECT id, identificador, modalidade_codigo, taxa_final_mes, cet_price_ano FROM operacoes;`.
**Commit → PR.**

### Critérios de aceite

- [ ] Parte A: `npm run schema` e `npm run seed` rodam sem erro na sua máquina; `.env` fora do git; `/api/health` devolve `banco: "ok"`.
- [ ] Cenário feliz devolve `201` com os valores do Anexo A.5 e a linha aparece na tabela.
- [ ] Os 5 cenários de erro devolvem o status e o `codigo` corretos, no formato padrão.
- [ ] Erros de validação listam **todos** os problemas em `detalhes`.
- [ ] Operação recusada (422) **não** é gravada.
- [ ] `npm test` passa (testes de taxa, validação e simulação incluídos).
- [ ] Nenhuma query monta SQL com concatenação de string.

### Armadilhas comuns

- `npm run dev` falha com `.env: not found` → você não criou o `.env` a partir do `.env.example`.
- `ER_ACCESS_DENIED_ERROR` → senha errada no `.env`. `ECONNREFUSED` → MySQL não está rodando. `ER_BAD_DB_ERROR` → faltou `npm run schema`.
- `ER_NO_REFERENCED_ROW_2` no `POST` → o código da modalidade não existe na tabela `modalidades`: faltou `npm run seed`, ou o seed está com códigos diferentes do catálogo da T-01. Avise a equipe de banco; **não** remova a chave estrangeira.
- `valor` volta como `"10000.00"` (string) → faltou `decimalNumbers: true` no pool.
- `dataLiberacao` volta como `2026-10-29T03:00:00.000Z` → faltou `dateStrings: true`.
- Resposta 500 em vez de 400/422 → você lançou `Error` comum em vez de `ErroDeNegocio`, ou o tratador de erros da T-01 não está registrado.
- Converter `/ 100` em dois lugares (no serviço e dentro de `calculaTaxa`) → taxa 100× menor. A conversão é **uma** e fica em `simulaOperacao`.

---

## T-08 — `GET /api/operacoes` (paginado) e `GET /api/operacoes/:id`

**Depende de:** T-07. **Arquivos:** altera `src/routes/operacoes.js` (o repositório já tem a função `listar`).

### O que é e por que existe

Depois de gravadas, as operações precisam ser consultadas: **uma** pelo `id` (resposta
completa, igual à do `POST`) ou **várias** em lista. A lista é **paginada**: em vez de devolver
mil operações de uma vez (lento, pesado), devolve "páginas" de N itens e informa quantas
páginas existem. A lista traz só um **resumo** de cada operação; o detalhe completo (com os 24
itens de cronograma) fica no `GET /:id`.

### Conceitos

**Paginação com `LIMIT` e `OFFSET`.** Se cada página tem `tamanho` itens, a página `pagina`
pula `(pagina − 1) × tamanho` itens:

```sql
SELECT ... FROM operacoes ORDER BY id DESC LIMIT 10 OFFSET 20;   -- página 3 de 10 em 10
```

`ORDER BY` é **obrigatório** — sem ele, a ordem entre páginas não é garantida e um item pode
aparecer em duas páginas. Ordenamos por `id DESC` (mais recente primeiro).

Para informar o total de páginas, uma segunda consulta: `SELECT COUNT(*) AS total FROM operacoes`.
`totalPaginas = Math.ceil(total / tamanho)`.

**Query string.** `GET /api/operacoes?pagina=2&tamanho=5` → `req.query.pagina === '2'` — vem
como **string**, sempre. Converta com `Number(...)` e valide.

### Contrato

```
GET /api/operacoes?pagina=1&tamanho=10
  pagina:  inteiro ≥ 1, padrão 1
  tamanho: inteiro de 1 a 100, padrão 10
  → 200   (valores abaixo são só ilustrativos do FORMATO — os seus dependem do que foi gravado)
  {
    "pagina": 1, "tamanho": 10, "total": 23, "totalPaginas": 3,
    "itens": [
      { "id": 23, "identificador": "OP-2026-0023", "modalidade": "VEICULOS", "valor": 35000,
        "score": 810, "prazoMeses": 36, "dataLiberacao": "2026-11-03", "faixaRisco": "A",
        "taxaFinalMes": 1.5, "cetPriceAno": 24.12, "cetSacAno": 24.30, "criadoEm": "2026-09-21 15:10:44" },
      "..."
    ]
  }
  → 400 DADOS_INVALIDOS se pagina/tamanho inválidos

GET /api/operacoes/:id
  → 200 com a operação completa (mesmo formato da resposta do POST)
  → 404 OPERACAO_NAO_ENCONTRADA
  → 400 DADOS_INVALIDOS se :id não for inteiro positivo
```

### Passo a passo

**1. Repositório — já pronto.** A função `listar({ pagina, tamanho })` já existe em
`src/repositorios/operacoes.js` (entregue pela equipe de banco). Leia para entender o que ela
devolve — repare que a coluna do banco é `modalidade_codigo`, mas o item sai como `modalidade`:

```js
export async function listar({ pagina, tamanho }) {
  const offset = (pagina - 1) * tamanho;
  const [linhas] = await pool.query(
    `SELECT id, identificador, modalidade_codigo, valor, score, prazo_meses, data_liberacao,
            faixa_risco, taxa_final_mes, cet_price_ano, cet_sac_ano, criado_em
       FROM operacoes
      ORDER BY id DESC
      LIMIT ? OFFSET ?`,
    [tamanho, offset],          // precisam ser NÚMEROS, não strings
  );
  const [[{ total }]] = await pool.query('SELECT COUNT(*) AS total FROM operacoes');
  const itens = linhas.map((l) => ({
    id: l.id, identificador: l.identificador,
    modalidade: l.modalidade_codigo,   // snake_case do banco -> nome do contrato da API
    valor: l.valor, score: l.score, prazoMeses: l.prazo_meses, dataLiberacao: l.data_liberacao,
    faixaRisco: l.faixa_risco, taxaFinalMes: l.taxa_final_mes,
    cetPriceAno: l.cet_price_ano, cetSacAno: l.cet_sac_ano, criadoEm: l.criado_em,
  }));
  return { itens, total };
}
```

**2. Na rota** (`src/routes/operacoes.js`), **antes** do `export default`:

```js
// GET /api/operacoes?pagina=&tamanho=
router.get('/', async (req, res) => {
  // 1. pagina = req.query.pagina === undefined ? 1 : Number(req.query.pagina)
  //    tamanho = req.query.tamanho === undefined ? 10 : Number(req.query.tamanho)
  // 2. valide: pagina inteiro ≥ 1; tamanho inteiro entre 1 e 100 → senão ErroDeNegocio 400 DADOS_INVALIDOS
  // 3. const { itens, total } = await repositorio.listar({ pagina, tamanho });
  // 4. res.json({ pagina, tamanho, total, totalPaginas: Math.ceil(total / tamanho), itens });
});

// GET /api/operacoes/:id
router.get('/:id', async (req, res) => {
  // 1. id = Number(req.params.id); se não for inteiro ≥ 1 → 400 DADOS_INVALIDOS
  // 2. const operacao = await repositorio.buscarPorId(id);
  // 3. if (!operacao) throw new ErroDeNegocio(404, 'OPERACAO_NAO_ENCONTRADA', `Operação ${id} não encontrada`);
  // 4. res.json(operacao);
});
```

Ordem importa: `router.get('/')` e `router.get('/:id')` podem ficar em qualquer ordem entre si,
mas ambos precisam estar **antes** do `export default router`.

**3. Teste no Postman.** Primeiro crie **12 operações** pelo `POST` da T-07 (mude o
`identificador` a cada uma: `OP-TESTE-01` … `OP-TESTE-12`). Depois:

| Requisição | Esperado |
|---|---|
| `GET /api/operacoes` | `200`, `pagina 1`, `tamanho 10`, `total ≥ 12`, `itens.length 10`, primeiro item = último criado |
| `GET /api/operacoes?pagina=2&tamanho=10` | `itens.length` = `total − 10` (se total < 20) |
| `GET /api/operacoes?pagina=1&tamanho=5` | `itens.length 5`, `totalPaginas = ceil(total/5)` |
| `GET /api/operacoes?pagina=999` | `200`, `itens: []` (página vazia não é erro) |
| `GET /api/operacoes?pagina=0` | `400 DADOS_INVALIDOS` |
| `GET /api/operacoes?tamanho=500` | `400 DADOS_INVALIDOS` |
| `GET /api/operacoes/1` | `200`, objeto completo com `simulacoes.PRICE.cronograma` de 12 itens |
| `GET /api/operacoes/999999` | `404 OPERACAO_NAO_ENCONTRADA` |
| `GET /api/operacoes/abc` | `400 DADOS_INVALIDOS` |

**Commit → PR.**

### Critérios de aceite

- [ ] Listagem paginada com `pagina`, `tamanho`, `total`, `totalPaginas` e `itens` em camelCase, ordenada do mais recente para o mais antigo.
- [ ] Itens da lista **não** incluem `simulacoes`/`cronograma` (só o resumo).
- [ ] Padrões `pagina=1`, `tamanho=10`; limites validados com 400.
- [ ] `GET /:id` devolve o mesmo formato do `POST`; 404 e 400 no formato padrão.
- [ ] Nenhum item repete entre a página 1 e a página 2.

### Armadilhas comuns

- `LIMIT ? OFFSET ?` com **strings** (`'10'`) → erro de sintaxe SQL. Converta com `Number` antes.
- Esquecer o `ORDER BY` → itens repetidos/pulados entre páginas.
- `Math.ceil(0 / 10)` = 0 → com tabela vazia `totalPaginas` é 0. Está correto; não force 1.
- Colocar a rota `/:id` sem validar `Number` → `GET /operacoes/abc` vira `WHERE id = NaN` e devolve 404 em vez de 400.

---

## Anexo A — Cenários de referência (valores esperados)

Todos calculados com as regras deste documento. Se o seu resultado difere, **o seu código está
errado** (ou você mudou uma regra — nesse caso, avise a equipe).

### A.1 Price — 10.000,00 a 2,00% a.m., 12 meses

`parcelaFixa 945,60` · `totalJuros 1.347,15` · `totalPago 11.347,15`

| nº | amortização | juros | valor | saldo devedor |
|---:|---:|---:|---:|---:|
| 1 | 745,60 | 200,00 | 945,60 | 9.254,40 |
| 2 | 760,51 | 185,09 | 945,60 | 8.493,89 |
| 3 | 775,72 | 169,88 | 945,60 | 7.718,17 |
| 4 | 791,24 | 154,36 | 945,60 | 6.926,93 |
| 5 | 807,06 | 138,54 | 945,60 | 6.119,87 |
| 6 | 823,20 | 122,40 | 945,60 | 5.296,67 |
| 7 | 839,67 | 105,93 | 945,60 | 4.457,00 |
| 8 | 856,46 | 89,14 | 945,60 | 3.600,54 |
| 9 | 873,59 | 72,01 | 945,60 | 2.726,95 |
| 10 | 891,06 | 54,54 | 945,60 | 1.835,89 |
| 11 | 908,88 | 36,72 | 945,60 | 927,01 |
| 12 | 927,01 | 18,54 | **945,55** | 0,00 |

### A.2 SAC — 10.000,00 a 2,00% a.m., 12 meses

`amortizacaoBase 833,33` · `totalJuros 1.300,00` · `totalPago 11.300,00`

| nº | amortização | juros | valor | saldo devedor |
|---:|---:|---:|---:|---:|
| 1 | 833,33 | 200,00 | 1.033,33 | 9.166,67 |
| 2 | 833,33 | 183,33 | 1.016,66 | 8.333,34 |
| 3 | 833,33 | 166,67 | 1.000,00 | 7.500,01 |
| 4 | 833,33 | 150,00 | 983,33 | 6.666,68 |
| 5 | 833,33 | 133,33 | 966,66 | 5.833,35 |
| 6 | 833,33 | 116,67 | 950,00 | 5.000,02 |
| 7 | 833,33 | 100,00 | 933,33 | 4.166,69 |
| 8 | 833,33 | 83,33 | 916,66 | 3.333,36 |
| 9 | 833,33 | 66,67 | 900,00 | 2.500,03 |
| 10 | 833,33 | 50,00 | 883,33 | 1.666,70 |
| 11 | 833,33 | 33,33 | 866,66 | 833,37 |
| 12 | **833,37** | 16,67 | 850,04 | 0,00 |

### A.3 Cronograma — liberação em 2026-10-30 (sexta-feira), 12 meses

| nº | data "aniversário" | vencimento | dias corridos | observação |
|---:|---|---|---:|---|
| 1 | 2026-11-30 | 2026-11-30 | 31 | segunda |
| 2 | 2026-12-30 | 2026-12-30 | 61 | |
| 3 | 2027-01-30 | **2027-02-01** | 94 | sábado → segunda |
| 4 | 2027-02-30 ✗ | **2027-03-01** | 122 | 30/02 não existe → 28/02 (domingo) → segunda |
| 5 | 2027-03-30 | 2027-03-30 | 151 | |
| 6 | 2027-04-30 | 2027-04-30 | 182 | |
| 7 | 2027-05-30 | **2027-05-31** | 213 | domingo → segunda |
| 8 | 2027-06-30 | 2027-06-30 | 243 | |
| 9 | 2027-07-30 | 2027-07-30 | 273 | |
| 10 | 2027-08-30 | 2027-08-30 | 304 | |
| 11 | 2027-09-30 | 2027-09-30 | 335 | |
| 12 | 2027-10-30 | **2027-11-01** | **367** | sábado → segunda; > 365 dias (limite do IOF atua) |

### A.4 Encargos e CET — sobre A.1/A.2 com o cronograma A.3

| | Price | SAC |
|---|---:|---:|
| IOF diário | 168,09 | 162,22 |
| IOF adicional (0,38%) | 38,00 | 38,00 |
| IOF total | 206,09 | 200,22 |
| Tarifa de cadastro (primeiro relacionamento) | 50,00 | 50,00 |
| **Encargos total** | **256,09** | **250,22** |
| Valor liberado (FC0) | 9.743,91 | 9.749,78 |
| **CET a.a.** | **33,25%** | — |
| **CET a.m.** | **2,42%** | — |
| Sanidade: CET a.m. sem encargos | 2,00% | — |

Demonstrativo (Price): Principal 10.000,00 (86,18%) · Juros 1.347,15 (11,61%) · IOF 206,09
(1,78%) · Tarifa 50,00 (0,43%) · somatório das parcelas 11.347,15 · total devido 11.603,24.

### A.5 Ponta a ponta — `POST /api/operacoes`

Entrada: `valor 10000`, `modalidade CONSIGNADO_INSS`, `score 650`, `prazoMeses 12`,
`dataLiberacao 2026-10-30`, `primeiroRelacionamento true`.

Taxa: faixa **B** (+0,50) → 1,60 + 0,50 = 2,10 → **teto 1,85% a.m.** (`tetoAplicado: true`).

| | PRICE | SAC |
|---|---:|---:|
| parcelaFixa / amortizacaoBase | 936,91 | 833,33 |
| 1ª parcela | 936,91 | 1.018,33 |
| 12ª parcela | 936,87 | 848,79 |
| totalJuros | 1.242,88 | 1.202,50 |
| totalPago (somatório das parcelas) | 11.242,88 | 11.202,50 |
| IOF (diário / adicional / total) | 167,65 / 38,00 / 205,65 | 162,22 / 38,00 / 200,22 |
| Tarifa de cadastro | 50,00 | 50,00 |
| Encargos total | 255,65 | 250,22 |
| valorLiberado | 9.744,35 | 9.749,78 |
| **CET a.a. / a.m.** | **30,89% / 2,27%** | **30,96% / 2,27%** |
| Total devido | 11.498,53 | 11.452,72 |

Segundo exemplo de taxa: `CREDITO_PESSOAL`, score 720 → faixa B → 4,50 + 0,50 = **5,00%**
(`tetoAplicado: false`).

## Anexo B — Catálogo de erros

| HTTP | `codigo` | Quando | Tarefa |
|---|---|---|---|
| 400 | `DADOS_INVALIDOS` | corpo ou query string inválidos; `detalhes` lista cada problema | T-07, T-08 |
| 404 | `MODALIDADE_NAO_ENCONTRADA` | `GET /modalidades/:codigo` com código inexistente | T-01 |
| 404 | `OPERACAO_NAO_ENCONTRADA` | `GET /operacoes/:id` com id inexistente | T-08 |
| 409 | `IDENTIFICADOR_DUPLICADO` | `POST /operacoes` com identificador já gravado | T-07 |
| 422 | `SCORE_INSUFICIENTE` | score na faixa E (0–199) | T-07 |
| 422 | `CET_NAO_CONVERGE` | bisseção não encontra raiz em [0, 1000% a.a.] | T-06 |
| 500 | `ERRO_INTERNO` | qualquer erro não previsto (banco fora, bug) — detalhes só no terminal | T-01 |
| 503 | — | `GET /health` quando o banco não responde | T-07 |

## Anexo C — Glossário

- **Amortização** — parte da parcela que reduz a dívida (o resto é juros).
- **Bisseção** — método de achar a raiz de uma função cortando um intervalo pela metade repetidamente.
- **CET** — Custo Efetivo Total: taxa anual que iguala o valor recebido ao valor presente de tudo que se paga. Res. CMN 4.881/2020.
- **Dias corridos** — contagem de calendário (inclui fins de semana), ao contrário de dias úteis.
- **FC0 / FCj** — fluxo de caixa inicial (o que o cliente recebe) e fluxos seguintes (o que paga).
- **IOF** — Imposto sobre Operações Financeiras. Parte diária (0,0082%/dia até 365 dias) + adicional (0,38%).
- **Modalidade** — tipo de crédito (consignado, veículos...), na nomenclatura do BCB.
- **Price** — sistema de parcelas fixas. **SAC** — sistema de amortização constante (parcelas decrescentes).
- **Spread** — acréscimo de taxa por risco, somado à taxa base.
- **Taxa efetiva composta** — juros sobre juros: `(1 + i)^n`. É a convenção do projeto e do BCB.
- **Teto** — taxa máxima permitida (regulatória ou de política).
- **UTC** — tempo universal, sem fuso; usado internamente para datas não "escorregarem" um dia.
