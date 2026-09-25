import { calculaPrice } from '../lib/price.js';
import { calculaSac } from '../lib/sac.js';
import { geraCronograma } from '../lib/cronograma.js';
import { calculaEncargos } from '../lib/encargos.js';
import { calculaCet } from '../lib/cet.js';
import { montaDemonstrativo } from '../lib/demonstrativo.js';
import { arredonda2 } from '../lib/util.js';
import { calculaTaxa } from './taxa.js';

// Junta tudo: descobre a taxa, roda Price e SAC, monta cronograma, encargos, CET e
// demonstrativo para os dois sistemas de amortização.
//
// entrada: saída de validaEntrada() — precisa ter valor, modalidade (objeto), score,
//          prazoMeses, dataLiberacao, primeiroRelacionamento.
export async function simulaOperacao(entrada) {
  const { valor, modalidade, score, prazoMeses, dataLiberacao, primeiroRelacionamento } = entrada;

  // 1. Taxa (pode lançar SCORE_INSUFICIENTE)
  const taxa = await calculaTaxa(modalidade, score);

  // 2. Único lugar do projeto onde % vira decimal
  const taxaMes = taxa.taxaFinalMes / 100;

  const simulacoes = {};

  for (const [nomeSistema, funcaoCalculo] of [
    ['PRICE', calculaPrice],
    ['SAC', calculaSac],
  ]) {
    const resultado = funcaoCalculo({ valor, taxaMes, prazoMeses });
    const cronograma = geraCronograma({ parcelas: resultado.parcelas, dataLiberacao });
    const encargos = calculaEncargos({ valor, cronograma, primeiroRelacionamento });
    const valorLiberado = arredonda2(valor - encargos.total);

    // Pode lançar CET_NAO_CONVERGE
    const cet = calculaCet({ valorLiberado, cronograma });

    const demonstrativo = montaDemonstrativo({
      valor,
      totalJuros: resultado.totalJuros,
      encargos,
      cronograma,
    });

    // Troca `parcelas` (sem data) pelo `cronograma` (com vencimento/diasCorridos)
    const { parcelas, ...resumo } = resultado;

    simulacoes[nomeSistema] = {
      ...resumo,
      encargos,
      valorLiberado,
      cet: {
        anualPercentual: arredonda2(cet.cetAnual * 100),
        mensalPercentual: arredonda2(cet.cetMensal * 100),
      },
      demonstrativo,
      cronograma,
    };
  }

  return {
    entrada: {
      valor,
      modalidade: modalidade.codigo,
      score,
      prazoMeses,
      dataLiberacao,
      primeiroRelacionamento,
    },
    taxa,
    simulacoes,
  };
}
