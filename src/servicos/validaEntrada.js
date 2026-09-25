import { buscarModalidade } from '../repositorios/modalidades.js';
import { ehDataValida } from '../lib/datas.js';
import { ErroDeNegocio } from '../lib/erros.js';

function hoje() {
  return new Date().toISOString().slice(0, 10);
}

// Valida o corpo do POST /api/operacoes e devolve a entrada normalizada.
// Junta TODOS os erros encontrados em `erros` (não para no primeiro), como o contrato exige.
//
// A modalidade agora vem do banco (repositorios/modalidades.js), não de um catálogo estático
// em memória — por isso esta função é assíncrona.
export async function validaEntrada(body) {
  const dados = body ?? {};
  const erros = [];

  // identificador: obrigatório, 1 a 60 caracteres
  const identificador = dados.identificador;
  if (typeof identificador !== 'string' || identificador.length < 1 || identificador.length > 60) {
    erros.push('identificador deve ser uma string entre 1 e 60 caracteres');
  }

  // valor: obrigatório, > 0 e <= 10.000.000
  const valor = dados.valor;
  const valorValido = typeof valor === 'number' && Number.isFinite(valor) && valor > 0 && valor <= 10000000;
  if (!valorValido) {
    erros.push('valor deve ser um número maior que zero e menor ou igual a 10.000.000');
  }

  // modalidade: obrigatória, precisa existir no banco
  let modalidadeObj;
  if (typeof dados.modalidade !== 'string' || dados.modalidade.length === 0) {
    erros.push('modalidade é obrigatória');
  } else {
    modalidadeObj = await buscarModalidade(dados.modalidade);
    if (!modalidadeObj) {
      erros.push(`modalidade "${dados.modalidade}" não existe`);
    }
  }

  // score: obrigatório, inteiro de 0 a 1000
  const score = dados.score;
  if (!Number.isInteger(score) || score < 0 || score > 1000) {
    erros.push('score deve ser um número inteiro entre 0 e 1000');
  }

  // prazoMeses: checagem básica sempre; checagem de faixa só se a modalidade foi encontrada
  const prazoMeses = dados.prazoMeses;
  if (!Number.isInteger(prazoMeses) || prazoMeses < 1) {
    erros.push('prazoMeses deve ser um número inteiro maior ou igual a 1');
  } else if (modalidadeObj && (prazoMeses < modalidadeObj.prazoMinMeses || prazoMeses > modalidadeObj.prazoMaxMeses)) {
    erros.push(
      `prazoMeses deve estar entre ${modalidadeObj.prazoMinMeses} e ${modalidadeObj.prazoMaxMeses} para ${modalidadeObj.codigo}`,
    );
  }

  // dataLiberacao: opcional, padrão hoje
  let dataLiberacao = dados.dataLiberacao;
  if (dataLiberacao === undefined) {
    dataLiberacao = hoje();
  } else if (!ehDataValida(dataLiberacao)) {
    erros.push('dataLiberacao deve ser uma data válida no formato AAAA-MM-DD');
  }

  // primeiroRelacionamento: opcional, padrão false
  let primeiroRelacionamento = dados.primeiroRelacionamento;
  if (primeiroRelacionamento === undefined) {
    primeiroRelacionamento = false;
  } else if (typeof primeiroRelacionamento !== 'boolean') {
    erros.push('primeiroRelacionamento deve ser um valor booleano (true ou false)');
  }

  if (erros.length > 0) {
    throw new ErroDeNegocio(400, 'DADOS_INVALIDOS', 'Há campos inválidos na requisição', erros);
  }

  return {
    identificador,
    valor,
    modalidade: modalidadeObj, // objeto completo, não só o código
    score,
    prazoMeses,
    dataLiberacao,
    primeiroRelacionamento,
  };
}
