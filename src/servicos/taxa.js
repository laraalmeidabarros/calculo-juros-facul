import { buscarFaixaPorScore } from '../repositorios/faixasJuros.js';
import { ErroDeNegocio } from '../lib/erros.js';

// Descobre a faixa de risco e a taxa final de uma modalidade para um score.
//
// Diferente do desenho original do backlog-api.md (que calculava
// `min(taxaBase + spread, teto)` dentro do código), aqui a taxa já vem PRONTA do banco:
// o time de dados gravou, em `faixas_juros`, uma linha por modalidade x faixa com o
// `taxa_mes` já calculado por essa mesma regra (ver §11 de docs/DOCUMENTACAO.md). Este
// serviço só busca essa linha e traduz para o formato que a API devolve.
//
// modalidade: objeto vindo de repositorios/modalidades.js (buscarModalidade) — precisa
//             ter `codigo` e `tetoTaxaMes`.
// score: inteiro de 0 a 1000.
export async function calculaTaxa(modalidade, score) {
  const faixaInfo = await buscarFaixaPorScore(modalidade.codigo, score);

  // faixaInfo vem undefined se a modalidade não existir ou o score estiver fora de 0..1000;
  // e taxa_mes vem null para a faixa E (score 0-199 = recusa), conforme o seed.
  if (!faixaInfo || faixaInfo.taxa_mes === null) {
    throw new ErroDeNegocio(422, 'SCORE_INSUFICIENTE', 'Score abaixo do mínimo para contratação');
  }

  const taxaFinalMes = faixaInfo.taxa_mes;

  return {
    faixaRisco: faixaInfo.faixa,
    taxaFinalMes,
    tetoTaxaMes: modalidade.tetoTaxaMes,
    tetoAplicado: taxaFinalMes >= modalidade.tetoTaxaMes,
  };
}
