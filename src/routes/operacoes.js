import { Router } from 'express';

import { validaEntrada } from '../servicos/validaEntrada.js';
import { simulaOperacao } from '../servicos/simulacao.js';
import * as repositorio from '../repositorios/operacoes.js';
import { ErroDeNegocio } from '../lib/erros.js';

const router = Router();

// POST /api/operacoes — T-07: valida, simula, grava e devolve a operação completa
router.post('/', async (req, res) => {
  const entrada = await validaEntrada(req.body); // 400 se inválido

  if (await repositorio.existeIdentificador(entrada.identificador)) {
    throw new ErroDeNegocio(
      409,
      'IDENTIFICADOR_DUPLICADO',
      `Já existe operação com identificador "${entrada.identificador}"`,
    );
  }

  const simulacao = await simulaOperacao(entrada); // 422 se score/CET

  const id = await repositorio.salvar({ identificador: entrada.identificador, ...simulacao });
  const operacao = await repositorio.buscarPorId(id);

  res.status(201).json(operacao);
});

// GET /api/operacoes?pagina=&tamanho= — T-08: listagem paginada
router.get('/', async (req, res) => {
  const pagina = req.query.pagina === undefined ? 1 : Number(req.query.pagina);
  const tamanho = req.query.tamanho === undefined ? 10 : Number(req.query.tamanho);

  const erros = [];
  if (!Number.isInteger(pagina) || pagina < 1) {
    erros.push('pagina deve ser um número inteiro maior ou igual a 1');
  }
  if (!Number.isInteger(tamanho) || tamanho < 1 || tamanho > 100) {
    erros.push('tamanho deve ser um número inteiro entre 1 e 100');
  }
  if (erros.length > 0) {
    throw new ErroDeNegocio(400, 'DADOS_INVALIDOS', 'Há campos inválidos na requisição', erros);
  }

  const { itens, total } = await repositorio.listar({ pagina, tamanho });

  res.json({
    pagina,
    tamanho,
    total,
    totalPaginas: Math.ceil(total / tamanho),
    itens,
  });
});

// GET /api/operacoes/:id — T-08: uma operação completa
router.get('/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1) {
    throw new ErroDeNegocio(400, 'DADOS_INVALIDOS', 'id deve ser um número inteiro positivo');
  }

  const operacao = await repositorio.buscarPorId(id);
  if (!operacao) {
    throw new ErroDeNegocio(404, 'OPERACAO_NAO_ENCONTRADA', `Operação ${id} não encontrada`);
  }

  res.json(operacao);
});

export default router;
